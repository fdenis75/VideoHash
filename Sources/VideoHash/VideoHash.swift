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
    private let oshashGenerator: OSHashGenerator
    private let phashGenerator: PHashGenerator
    private let logger = Logger.videoHash

    /// Initialize a video hash generator
    /// - Parameter configuration: Configuration for hash generation (defaults to .default)
    public init(configuration: HashConfiguration = .default) {
        self.configuration = configuration
        self.oshashGenerator = OSHashGenerator()
        self.phashGenerator = PHashGenerator(configuration: configuration)

        logger.info("VideoHashGenerator initialized")
    }

    /// Generate both PHash and OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: HashResult containing both hashes and video duration
    /// - Throws: HashError if video cannot be processed
    @available(iOS 15, *)
    public func generateHashes(for videoURL: URL) async throws -> HashResult {
        logger.info("Generating hashes for: \(videoURL.path)")

        // Validate configuration
        try configuration.validate()

        // Validate video file
        try await validateVideoFile(videoURL)

        // Get video duration
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds

        // Generate both hashes concurrently
        async let phash = phashGenerator.generateHash(for: videoURL, asset: asset)
        async let oshash = oshashGenerator.generateHash(for: videoURL)

        let (phashValue, oshashValue) = try await (phash, oshash)

        let result = HashResult(
            phash: phashValue,
            oshash: oshashValue,
            duration: duration
        )

        logger.info("Generated hashes successfully: phash=\(phashValue), oshash=\(oshashValue)")

        return result
    }

    /// Generate only PHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: Lowercase hexadecimal string representing the PHash
    /// - Throws: HashError if video cannot be processed
    public func generatePHash(for videoURL: URL) async throws -> String {
        logger.info("Generating PHash for: \(videoURL.path)")

        try configuration.validate()
        try await validateVideoFile(videoURL)

        let asset = AVURLAsset(url: videoURL)
        let phash = try await phashGenerator.generateHash(for: videoURL, asset: asset)

        logger.info("Generated PHash: \(phash)")

        return phash
    }

    /// Generate only OSHash for a video file
    /// - Parameter videoURL: URL of the video file
    /// - Returns: 16-character hex string representing the OSHash
    /// - Throws: HashError if video cannot be processed
    public func generateOSHash(for videoURL: URL) async throws -> String {
        logger.info("Generating OSHash for: \(videoURL.path)")

        let oshash = try await oshashGenerator.generateHash(for: videoURL)

        logger.info("Generated OSHash: \(oshash)")

        return oshash
    }

    // MARK: - Private Helpers

    /// Validate video file exists and is accessible
    /// - Parameter url: URL of the video file
    /// - Throws: HashError if file doesn't exist or is not a valid video
    private func validateVideoFile(_ url: URL) async throws {
        let path = url.path
        let fileManager = FileManager.default

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
    }
}
