//
//  VideoHash.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import AVFoundation
import Logging

/// Main entry point for video hash generation
///
/// VideoHashGenerator coordinates PHash and OSHash generation for video files.
/// It uses AVFoundation for video processing and provides actor-based concurrency
/// for thread-safe hash generation.
///
/// Example usage:
/// ```swift
/// let generator = VideoHashGenerator()
/// let result = try await generator.generateHashes(for: videoURL)
/// print("PHash: \(result.phash)")
/// print("OSHash: \(result.oshash)")
/// ```
@available(iOS 13.0.0, *)
public actor VideoHashGenerator: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.videoHash

    /// Initialize a video hash generator
    /// - Parameter configuration: Configuration for hash generation (defaults to .default)
    public init(configuration: HashConfiguration = .default) {
        self.configuration = configuration

        logger.info("VideoHashGenerator initialized")
    }

    /// Generate both PHash and OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: HashResult containing both hashes and video duration
    /// - Throws: HashError if video cannot be processed
    @available(iOS 15, *)
    public func generateHashes(for videoURL: URL) async throws -> HashResult {
        try configuration.validate()
        return try await Self.generateHashesForSingleVideo(videoURL, configuration: configuration)
    }

    /// Generate both PHash and OSHash for multiple video files concurrently.
    ///
    /// The returned array preserves the same order as the input `videoURLs`.
    /// Scheduling is volume-aware: the generator interleaves files across volumes
    /// when possible before applying the concurrency limit.
    ///
    /// - Parameters:
    ///   - videoURLs: URLs of the video files to hash.
    ///   - maxConcurrentTasks: Maximum number of files to process at once. Must be greater than zero.
    /// - Returns: Hash results in the same order as `videoURLs`.
    /// - Throws: HashError if configuration is invalid or if any file fails to process.
    @available(iOS 15, *)
    public func generateHashes(
        for videoURLs: [URL],
        maxConcurrentTasks: Int
    ) async throws -> [HashResult] {
        try configuration.validate()

        guard maxConcurrentTasks > 0 else {
            throw HashError.processingFailed(reason: "maxConcurrentTasks must be greater than zero")
        }

        guard !videoURLs.isEmpty else {
            return []
        }

        let configuration = self.configuration
        let plan = HashBatchPlanner.makePlan(for: videoURLs)
        let concurrencyLimit = min(maxConcurrentTasks, plan.count)

        logger.info(
            "Generating hashes for \(plan.count) videos with concurrency limit \(concurrencyLimit)"
        )

        return try await withThrowingTaskGroup(of: (Int, HashResult).self) { group in
            var results = [HashResult?](repeating: nil, count: videoURLs.count)
            var nextItemIndex = 0

            func addNextTaskIfAvailable() {
                guard nextItemIndex < plan.count else {
                    return
                }

                let item = plan[nextItemIndex]
                nextItemIndex += 1

                group.addTask {
                    let result = try await Self.generateHashesForSingleVideo(
                        item.url,
                        configuration: configuration
                    )
                    return (item.originalIndex, result)
                }
            }

            for _ in 0..<concurrencyLimit {
                addNextTaskIfAvailable()
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                addNextTaskIfAvailable()
            }

            return try results.enumerated().map { index, result in
                guard let result else {
                    throw HashError.processingFailed(reason: "Missing batch result at index \(index)")
                }
                return result
            }
        }
    }

    /// Generate only PHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: Lowercase hexadecimal string representing the PHash
    /// - Throws: HashError if video cannot be processed
    public func generatePHash(for videoURL: URL) async throws -> String {
        try configuration.validate()
        return try await Self.generatePHashForSingleVideo(videoURL, configuration: configuration)
    }

    /// Generate only OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: 16-character hex string representing the OSHash
    /// - Throws: HashError if video cannot be processed
    public func generateOSHash(for videoURL: URL) async throws -> String {
        try configuration.validate()
        return try await Self.generateOSHashForSingleVideo(videoURL, configuration: configuration)
    }

    // MARK: - Private Helpers

    /// Validate video file exists and is accessible
    /// - Parameter url: URL of the video file
    /// - Throws: HashError if file doesn't exist or is not a valid video
    private static func validateVideoFile(_ url: URL) async throws {
        let path = url.path
        let fileManager = FileManager.default
        let logger = Logger.videoHash

        guard fileManager.fileExists(atPath: path) else {
            logger.error("Video file not found: \(path)")
            throw HashError.fileNotFound(path: path)
        }

        // Check if file is readable
        guard fileManager.isReadableFile(atPath: path) else {
            logger.error("Video file not readable: \(path)")
            throw HashError.invalidVideoFile(path: path, reason: "File is not readable")
        }

        // Basic validation using AVFoundation
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)

        guard !tracks.isEmpty else {
            logger.error("No tracks found in video: \(path)")
            throw HashError.invalidVideoFile(path: path, reason: "No video tracks found")
        }

        // Verify at least one video track exists
        let hasVideoTrack = tracks.contains(where: { $0.mediaType == .video })

        guard hasVideoTrack else {
            logger.error("No video tracks found: \(path)")
            throw HashError.invalidVideoFile(path: path, reason: "No video tracks found")
        }
        logger.info("validated: \(path)")
    }

    private static func generateHashesForSingleVideo(
        _ videoURL: URL,
        configuration: HashConfiguration
    ) async throws -> HashResult {
        let logger = Logger.videoHash
        logger.info("Generating hashes for: \(videoURL.path)")

        try await validateVideoFile(videoURL)

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let phashGenerator = PHashGenerator(configuration: configuration)
        let oshashGenerator = OSHashGenerator()

        async let phash = phashGenerator.generateHash(for: videoURL, asset: asset)
        async let oshash = oshashGenerator.generateHash(for: videoURL)

        let result = try await HashResult(
            phash: phash,
            oshash: oshash,
            duration: duration
        )

        logger.info(
            "Generated hashes successfully: phash=\(result.phash), oshash=\(result.oshash)"
        )

        return result
    }

    private static func generatePHashForSingleVideo(
        _ videoURL: URL,
        configuration: HashConfiguration
    ) async throws -> String {
        let logger = Logger.videoHash
        logger.info("Generating PHash for: \(videoURL.path)")

        try await validateVideoFile(videoURL)

        let asset = AVURLAsset(url: videoURL)
        let phash = try await PHashGenerator(configuration: configuration)
            .generateHash(for: videoURL, asset: asset)

        logger.info("Generated PHash: \(phash)")
        return phash
    }

    private static func generateOSHashForSingleVideo(
        _ videoURL: URL,
        configuration: HashConfiguration
    ) async throws -> String {
        let logger = Logger.videoHash
        logger.info("Generating OSHash for: \(videoURL.path)")

        let oshash = try await OSHashGenerator().generateHash(for: videoURL)
        logger.info("Generated OSHash: \(oshash)")
        return oshash
    }
}
