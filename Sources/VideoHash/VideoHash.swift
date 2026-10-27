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
    private let extractionPolicy: FFmpegExtractionPolicy
    private let logger = Logger.videoHash

    /// Initialize a video hash generator
    /// - Parameter configuration: Configuration for hash generation (defaults to .default)
    public init(configuration: HashConfiguration = .default) {
        self.configuration = configuration
        self.extractionPolicy = .production

        logger.info("VideoHashGenerator initialized")
    }

    /// Effective default for package-local benchmark metadata.
    package static var defaultFFmpegInputsPerProcess: Int? { FFmpegExtractionPolicy.production.maxInputsPerProcess }

    /// Package-only entry point for resource-policy benchmarks; nil selects production policy.
    package init(
        configuration: HashConfiguration,
        ffmpegMaxInputsPerProcess: Int?,
        onFFmpegLaunchAttempt: (@Sendable () -> Void)? = nil
    ) throws {
        self.configuration = configuration
        var policy = try ffmpegMaxInputsPerProcess.map { try FFmpegExtractionPolicy(maxInputsPerProcess: $0) } ?? .production
        if let onFFmpegLaunchAttempt { policy.onLaunchAttempt = { _ in onFFmpegLaunchAttempt() } }
        self.extractionPolicy = policy
    }

    /// Generate both PHash and OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: HashResult containing both hashes and video duration
    /// - Throws: HashError if video cannot be processed
    @available(iOS 15, *)
    public func generateHashes(for videoURL: URL) async throws -> HashResult {
        try Task.checkCancellation()
        try configuration.validate()
        return try await Self.generateHashesForSingleVideo(videoURL, configuration: configuration, extractionPolicy: extractionPolicy)
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
        try Task.checkCancellation()
        try configuration.validate()

        guard maxConcurrentTasks > 0 else {
            throw HashError.processingFailed(reason: "maxConcurrentTasks must be greater than zero")
        }

        guard !videoURLs.isEmpty else {
            return []
        }

        let configuration = self.configuration
        let extractionPolicy = self.extractionPolicy
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
                    try Task.checkCancellation()
                    let result = try await Self.generateHashesForSingleVideo(
                        item.url,
                        configuration: configuration,
                        extractionPolicy: extractionPolicy
                    )
                    return (item.originalIndex, result)
                }
            }

            for _ in 0..<concurrencyLimit {
                addNextTaskIfAvailable()
            }

            while let (index, result) = try await group.next() {
                try Task.checkCancellation()
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

    /// Generate hashes for multiple videos, yielding each completed video immediately.
    ///
    /// Elements arrive in completion order, with the original input index and URL
    /// so callers can associate results even when an input URL occurs more than once.
    /// Each element contains a success or the original error for that file. File
    /// failures do not stop the queue. The stream buffers outcomes without dropping any.
    /// Cancelling the consuming task cancels hashing. If you stop iteration early,
    /// release the stream and its iterator or cancel the consuming task to stop work.
    ///
    /// - Parameters:
    ///   - videoURLs: URLs of the video files to hash.
    ///   - maxConcurrentTasks: Maximum files processed at once; must be positive.
    /// - Returns: A stream of per-file outcomes. Invalid batch configuration and
    ///   cancellation terminate the stream with an error during iteration.
    @available(iOS 15, *)
    public func generateHashesStream(
        for videoURLs: [URL],
        maxConcurrentTasks: Int
    ) -> AsyncThrowingStream<(index: Int, url: URL, result: Result<HashResult, any Error>), any Error> {
        let configuration = self.configuration
        let extractionPolicy = self.extractionPolicy
        let initiallyCancelled = Task.isCancelled

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    if initiallyCancelled { throw CancellationError() }
                    try Task.checkCancellation()
                    try configuration.validate()
                    guard maxConcurrentTasks > 0 else {
                        throw HashError.processingFailed(reason: "maxConcurrentTasks must be greater than zero")
                    }

                    let plan = HashBatchPlanner.makePlan(for: videoURLs)
                    try await withThrowingTaskGroup(of: (Int, Result<HashResult, any Error>).self) { group in
                        var nextItemIndex = 0

                        func addNextTaskIfAvailable() {
                            guard nextItemIndex < plan.count else { return }
                            let item = plan[nextItemIndex]
                            nextItemIndex += 1
                            group.addTask {
                                try Task.checkCancellation()
                                do {
                                    let result = try await Self.generateHashesForSingleVideo(
                                        item.url,
                                        configuration: configuration,
                                        extractionPolicy: extractionPolicy
                                    )
                                    try Task.checkCancellation()
                                    return (item.originalIndex, .success(result))
                                } catch {
                                    try Task.checkCancellation()
                                    return (item.originalIndex, .failure(error))
                                }
                            }
                        }

                        for _ in 0..<min(maxConcurrentTasks, plan.count) {
                            addNextTaskIfAvailable()
                        }
                        while let (index, result) = try await group.next() {
                            try Task.checkCancellation()
                            if case .terminated = continuation.yield((index, videoURLs[index], result)) {
                                group.cancelAll()
                                return
                            }
                            addNextTaskIfAvailable()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    /// Generate only PHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: Lowercase hexadecimal string representing the PHash
    /// - Throws: HashError if video cannot be processed
    public func generatePHash(for videoURL: URL) async throws -> String {
        try Task.checkCancellation()
        try configuration.validate()
        return try await Self.generatePHashForSingleVideo(videoURL, configuration: configuration, extractionPolicy: extractionPolicy)
    }

    /// Generate only OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: 16-character hex string representing the OSHash
    /// - Throws: HashError if video cannot be processed
    public func generateOSHash(for videoURL: URL) async throws -> String {
        try Task.checkCancellation()
        try configuration.validate()
        return try await Self.generateOSHashForSingleVideo(videoURL, configuration: configuration)
    }

    // MARK: - Private Helpers

    /// Validate video file exists and is accessible
    /// - Parameter url: URL of the video file
    /// - Throws: HashError if file doesn't exist or is not a valid video
    private static func validatedAsset(for url: URL) async throws -> AVURLAsset {
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
        return asset
    }

    private static func generateHashesForSingleVideo(
        _ videoURL: URL,
        configuration: HashConfiguration,
        extractionPolicy: FFmpegExtractionPolicy
    ) async throws -> HashResult {
        let logger = Logger.videoHash
        logger.info("Generating hashes for: \(videoURL.path)")

        let asset = try await validatedAsset(for: videoURL)
        try Task.checkCancellation()
        let duration = try await asset.load(.duration).seconds
        let phashGenerator = PHashGenerator(configuration: configuration, extractionPolicy: extractionPolicy)
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
        configuration: HashConfiguration,
        extractionPolicy: FFmpegExtractionPolicy
    ) async throws -> String {
        let logger = Logger.videoHash
        logger.info("Generating PHash for: \(videoURL.path)")

        let asset = try await validatedAsset(for: videoURL)
        try Task.checkCancellation()
        let phash = try await PHashGenerator(configuration: configuration, extractionPolicy: extractionPolicy)
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
