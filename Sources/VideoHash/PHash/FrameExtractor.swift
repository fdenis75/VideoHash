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

        // Single ffmpeg process: one seeked input per sample time, combined via
        // filter_complex (scale -> tile -> resize -> grayscale). Replaces 25
        // frame-extraction processes + 1 tiling process with one process, and drops
        // the lossy per-frame JPEG round-trip the old two-pass pipeline went through.
        let rawPath = tempDirectory.appendingPathComponent("gray-\(configuration.dctSize).raw").path
        try runFFmpegExtractAndTile(
            ffmpegPath: ffmpegPath,
            videoPath: url.path,
            sampleTimes: sampleTimes,
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

        try runFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg",
            exitFailureReason: "ffmpeg",
            failureReason: HashError.frameExtractionFailed
        )
    }

    /// Extract all sample frames and tile them into a grayscale sprite in a single
    /// ffmpeg process: one `-ss`/`-i` pair per sample time (each still seeks and
    /// decodes independently, matching the per-frame timestamps of the old
    /// multi-process pipeline), joined by a filter_complex that scales each frame,
    /// tiles them into the sprite grid, then resizes and converts to grayscale.
    private func runFFmpegExtractAndTile(
        ffmpegPath: String,
        videoPath: String,
        sampleTimes: [Double],
        outputPath: String
    ) throws {
        var arguments = ["-v", "error"]
        for time in sampleTimes {
            arguments += ["-ss", String(format: "%.6f", time), "-i", videoPath]
        }

        var filterParts: [String] = []
        for index in 0..<sampleTimes.count {
            filterParts.append("[\(index):v]scale=\(configuration.frameWidth):-1[v\(index)]")
        }
        // `tile` consumes consecutive frames from a single stream (it has no
        // multi-pad form like hstack/vstack), so the per-frame streams must be
        // concatenated into one stream before tiling.
        let concatInputs = (0..<sampleTimes.count).map { "[v\($0)]" }.joined()
        filterParts.append("\(concatInputs)concat=n=\(sampleTimes.count):v=1:a=0[allframes]")
        filterParts.append(
            "[allframes]tile=\(configuration.spriteColumns)x\(configuration.spriteRows):padding=0:margin=0[tiled]"
        )
        filterParts.append(
            "[tiled]scale=\(configuration.dctSize):\(configuration.dctSize):flags=bilinear,format=gray[out]"
        )

        arguments += [
            "-filter_complex", filterParts.joined(separator: ";"),
            "-map", "[out]",
            "-frames:v", "1",
            "-f", "rawvideo",
            "-pix_fmt", "gray",
            "-y", outputPath
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments

        try runFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg extract+tile",
            exitFailureReason: "ffmpeg extract+tile",
            failureReason: HashError.processingFailed
        )
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

        try runFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg tile preprocess",
            exitFailureReason: "ffmpeg tile preprocess",
            failureReason: HashError.processingFailed
        )
    }

    /// Runs an ffmpeg process, draining stderr to a temp file as it writes rather than
    /// buffering it in a `Pipe` and reading it back after `waitUntilExit()`. A `Pipe`'s
    /// kernel buffer is only ~64KB; a corrupt input can make ffmpeg log far more than that
    /// (thousands of "Invalid NAL unit size" lines even at `-v error`), so reading the pipe
    /// only after exit deadlocks: ffmpeg blocks on write() while nothing drains the pipe, and
    /// waitUntilExit() never returns.
    private func runFFmpegProcess(
        _ process: Process,
        launchFailureReason: String,
        exitFailureReason: String,
        failureReason: (String) -> HashError
    ) throws {
        let fileManager = FileManager.default
        let stderrURL = fileManager.temporaryDirectory.appendingPathComponent(
            "videohash-ffmpeg-stderr-\(UUID().uuidString).log"
        )
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? fileManager.removeItem(at: stderrURL)
        }

        guard let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path) else {
            throw failureReason("Failed to create stderr log file for ffmpeg")
        }

        process.standardError = stderrHandle
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? stderrHandle.close()
            throw failureReason("\(launchFailureReason): \(error.localizedDescription)")
        }
        try? stderrHandle.close()

        guard process.terminationStatus == 0 else {
            let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
            let stderrOutput = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown ffmpeg error"
            throw failureReason(
                "\(exitFailureReason) exited with status \(process.terminationStatus): \(stderrOutput)"
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
