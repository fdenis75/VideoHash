//
//  FrameExtractor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import Logging

/// Extracts frames from video files for PHash generation.
actor FrameExtractor: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Extract frames from video for PHash generation
    /// - Parameters:
    ///   - asset: AVURLAsset for the video
    ///   - url: URL of the video file
    /// - Returns: Array of CGImages resized to configured width
    /// - Throws: HashError if frame extraction fails
    func extractFrames(from asset: AVURLAsset, url: URL) async throws -> [CGImage] {
        logger.debug("Extracting \(configuration.frameCount) frames from: \(url.path)")

        // Get video duration
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds > 0 else {
            throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
        }

        let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
        logger.debug("Extracting frames at times: \(sampleTimes)")

        if configuration.useFFmpegFrameExtraction {
            let frames = try extractFramesWithFFmpeg(from: url, sampleTimes: sampleTimes)
            logger.info("Successfully extracted \(frames.count) frames with ffmpeg")
            return frames
        } else {
            let frames = try await extractFramesWithAVFoundation(asset: asset, sampleTimes: sampleTimes)
            logger.info("Successfully extracted \(frames.count) frames with AVFoundation")
            return frames
        }
    }

    /// Extract and preprocess frames with an ffmpeg pipeline equivalent to videohashes:
    /// extract 25 scaled frames -> tile into 5x5 sprite -> bilinear resize to DCT size -> grayscale bytes.
    func extractPreprocessedPixels(from asset: AVURLAsset, url: URL) async throws -> [Float] {
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds > 0 else {
            throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
        }

        let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
        let ffmpegPath = try resolveFFmpegPath()
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "videohash-preprocess-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        for (index, time) in sampleTimes.enumerated() {
            let framePath = tempDirectory
                .appendingPathComponent(String(format: "frame-%04d.jpg", index))
                .path
            try runFFmpegFrameExtraction(
                ffmpegPath: ffmpegPath,
                videoPath: url.path,
                timestamp: time,
                outputPath: framePath
            )
        }

        let rawPath = tempDirectory.appendingPathComponent("gray-\(configuration.dctSize).raw").path
        try runFFmpegTilePreprocess(
            ffmpegPath: ffmpegPath,
            inputPattern: tempDirectory.appendingPathComponent("frame-%04d.jpg").path,
            outputPath: rawPath
        )

        let rawData = try Data(contentsOf: URL(fileURLWithPath: rawPath))
        let pixelCount = configuration.dctSize * configuration.dctSize
        guard rawData.count >= pixelCount else {
            throw HashError.processingFailed(
                reason: "Preprocessed grayscale output too small: expected \(pixelCount), got \(rawData.count)"
            )
        }

        var pixels = [Float](repeating: 0.0, count: pixelCount)
        rawData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let bytePointer = bytes.bindMemory(to: UInt8.self)
            for i in 0..<pixelCount {
                pixels[i] = Float(bytePointer[i]) / 255.0
            }
        }
        return pixels
    }

    // MARK: - Shared helpers

    /// Matches videohashes sampling: start at 5%, then 25 steps of 90% / frameCount.
    private func makeSampleTimes(durationSeconds: Double) throws -> [Double] {
        guard configuration.frameCount > 0 else {
            throw HashError.processingFailed(reason: "Frame count must be positive")
        }

        let startTime = durationSeconds * 0.05
        let step = (durationSeconds * 0.9) / Double(configuration.frameCount)

        return (0..<configuration.frameCount).map { index in
            startTime + (Double(index) * step)
        }
    }

    private func normalizeFrameCount(_ frames: [CGImage]) throws -> [CGImage] {
        guard frames.count >= configuration.frameCount / 2 else {
            logger.error("Insufficient frames extracted: \(frames.count)/\(configuration.frameCount)")
            throw HashError.insufficientFrames(
                expected: configuration.frameCount,
                actual: frames.count
            )
        }

        var normalizedFrames = frames
        while normalizedFrames.count < configuration.frameCount {
            guard let lastFrame = normalizedFrames.last else {
                throw HashError.insufficientFrames(
                    expected: configuration.frameCount,
                    actual: normalizedFrames.count
                )
            }
            normalizedFrames.append(lastFrame)
            logger.debug("Duplicating frame to reach target count")
        }

        return normalizedFrames
    }

    // MARK: - FFmpeg extraction

    private func extractFramesWithFFmpeg(from url: URL, sampleTimes: [Double]) throws -> [CGImage] {
        let ffmpegPath = try resolveFFmpegPath()
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "videohash-frames-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(configuration.frameCount)

        for (index, time) in sampleTimes.enumerated() {
            let outputURL = tempDirectory.appendingPathComponent("frame-\(index).jpg")
            try runFFmpegFrameExtraction(
                ffmpegPath: ffmpegPath,
                videoPath: url.path,
                timestamp: time,
                outputPath: outputURL.path
            )

            guard let imageSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw HashError.frameExtractionFailed(reason: "Failed to decode ffmpeg output frame \(index)")
            }
            frames.append(image)
        }

        return try normalizeFrameCount(frames)
    }

    private func runFFmpegFrameExtraction(
        ffmpegPath: String,
        videoPath: String,
        timestamp: Double,
        outputPath: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-v", "error",
            "-ss", String(format: "%.6f", timestamp),
            "-i", videoPath,
            "-frames:v", "1",
            "-vf", "scale=\(configuration.frameWidth):-1",
            "-y",
            outputPath
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw HashError.frameExtractionFailed(reason: "Failed to launch ffmpeg: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown ffmpeg error"
            throw HashError.frameExtractionFailed(
                reason: "ffmpeg exited with status \(process.terminationStatus): \(stderrOutput)"
            )
        }
    }

    private func runFFmpegTilePreprocess(
        ffmpegPath: String,
        inputPattern: String,
        outputPath: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-v", "error",
            "-framerate", "1",
            "-i", inputPattern,
            "-frames:v", "1",
            "-vf", "tile=\(configuration.spriteColumns)x\(configuration.spriteRows):padding=0:margin=0,scale=\(configuration.dctSize):\(configuration.dctSize):flags=bilinear,format=gray",
            "-f", "rawvideo",
            "-pix_fmt", "gray",
            "-y",
            outputPath
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw HashError.processingFailed(reason: "Failed to launch ffmpeg tile preprocess: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown ffmpeg error"
            throw HashError.processingFailed(
                reason: "ffmpeg tile preprocess exited with status \(process.terminationStatus): \(stderrOutput)"
            )
        }
    }

    private func resolveFFmpegPath() throws -> String {
        try FFmpegPathResolver().resolve(configuredPath: configuration.ffmpegPath)
    }

    // MARK: - AVFoundation fallback

    private func extractFramesWithAVFoundation(asset: AVURLAsset, sampleTimes: [Double]) async throws -> [CGImage] {
        let timePoints = sampleTimes.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
        imageGenerator.requestedTimeToleranceAfter = .positiveInfinity

        // Preserve aspect ratio by constraining width and allowing a large maximum height.
        imageGenerator.maximumSize = CGSize(width: configuration.frameWidth, height: 10_000)

        var frames: [CGImage] = []
        frames.reserveCapacity(configuration.frameCount)

        for time in timePoints {
            do {
                let (image, _) = try await imageGenerator.image(at: time)
                frames.append(image)
                logger.trace("Extracted frame at \(time.seconds)s")
            } catch {
                logger.warning("Failed to extract frame at \(time.seconds)s: \(error.localizedDescription)")
            }
        }

        return try normalizeFrameCount(frames)
    }
}
