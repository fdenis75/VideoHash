//
//  FrameExtractor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import AVFoundation
import CoreGraphics
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
    /// - Returns: Frames scaled to the configured width
    /// - Throws: HashError if frame extraction fails
    func extractFrames(from asset: AVURLAsset, url: URL) async throws -> [RGBImage] {
        logger.debug("Extracting \(configuration.frameCount) frames from: \(url.path)")

        if configuration.useFFmpegFrameExtraction {
            let ffmpegPath = try resolveFFmpegPath()
            let durationSeconds = try await probeDuration(ffmpegPath: ffmpegPath, url: url, asset: asset)
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            logger.debug("Extracting frames at times: \(sampleTimes)")

            let frames = try extractFramesWithFFmpeg(ffmpegPath: ffmpegPath, url: url, sampleTimes: sampleTimes)
            logger.info("Successfully extracted \(frames.count) frames with ffmpeg")
            return frames
        } else {
            let durationSeconds = try await asset.load(.duration).seconds
            guard durationSeconds > 0 else {
                throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
            }
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            logger.debug("Extracting frames at times: \(sampleTimes)")

            let frames = try await extractFramesWithAVFoundation(asset: asset, sampleTimes: sampleTimes)
            logger.info("Successfully extracted \(frames.count) frames with AVFoundation")
            return try frames.map { try RGBImage(cgImage: $0) }
        }
    }

    // MARK: - Shared helpers

    /// Matches videohashes sampling: start at 5%, then 25 steps of 90% / frameCount.
    private func makeSampleTimes(durationSeconds: Double) throws -> [Double] {
        guard configuration.frameCount > 0 else {
            throw HashError.processingFailed(reason: "Frame count must be positive")
        }

        let startTime = 0.05 * durationSeconds
        let step = (0.9 * durationSeconds) / Double(configuration.frameCount)

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

    // MARK: - Duration

    /// Duration as videohashes sees it: the container duration reported by ffmpeg,
    /// rounded to 0.01s (stash rounds ffprobe's `format.duration` the same way).
    ///
    /// AVFoundation's duration can differ noticeably (e.g. 21.38s vs 21.43s), which
    /// shifts every sample timestamp, so it is only used when ffmpeg reports none.
    private func probeDuration(ffmpegPath: String, url: URL, asset: AVURLAsset) async throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-hide_banner", "-i", url.path]

        // ffmpeg exits non-zero here because no output is given; only stderr matters.
        let (_, stderrOutput) = try runFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg duration probe",
            failureReason: HashError.frameExtractionFailed
        )

        if let duration = Self.parseDuration(fromFFmpegOutput: stderrOutput), duration > 0 {
            return duration
        }

        logger.warning("ffmpeg reported no duration for \(url.path), falling back to AVFoundation")
        let durationSeconds = try await asset.load(.duration).seconds
        guard durationSeconds > 0 else {
            throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
        }
        return (durationSeconds * 100).rounded() / 100
    }

    /// Parse `Duration: HH:MM:SS.cc` from ffmpeg's input dump.
    static func parseDuration(fromFFmpegOutput output: String) -> Double? {
        guard let match = output.firstMatch(of: /Duration: (\d+):(\d{2}):(\d{2})\.(\d{2})/),
              let hours = Int(match.1),
              let minutes = Int(match.2),
              let seconds = Int(match.3),
              let centiseconds = Int(match.4) else {
            return nil
        }

        // Integer centiseconds / 100 gives the same Double as Go's math.Round(d*100)/100.
        let totalCentiseconds = ((hours * 60 + minutes) * 60 + seconds) * 100 + centiseconds
        return Double(totalCentiseconds) / 100
    }

    // MARK: - FFmpeg extraction

    /// Extract one frame per sample time exactly like stash's `generateSpriteScreenshot`.
    ///
    /// All frames are first extracted by a single ffmpeg process (one seeked input and
    /// one BMP output per sample time). Each output is produced with the same options
    /// as the reference's per-frame command, so the pixels are identical. If that fails,
    /// frames are extracted one process at a time with stash's fallback: fast seek
    /// first, then accurate seek for the remaining frames once a fast seek fails.
    private func extractFramesWithFFmpeg(ffmpegPath: String, url: URL, sampleTimes: [Double]) throws -> [RGBImage] {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "videohash-frames-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let outputURLs = sampleTimes.indices.map {
            tempDirectory.appendingPathComponent("frame-\($0).bmp")
        }

        do {
            try runFFmpegBatchExtraction(
                ffmpegPath: ffmpegPath,
                videoPath: url.path,
                sampleTimes: sampleTimes,
                outputPaths: outputURLs.map(\.path)
            )
            return try outputURLs.map { try BMPDecoder.decode(Data(contentsOf: $0)) }
        } catch {
            logger.warning("Batch frame extraction failed, extracting frames one by one: \(error.localizedDescription)")
        }

        var frames: [RGBImage] = []
        frames.reserveCapacity(sampleTimes.count)
        var slowSeek = false

        for (time, outputURL) in zip(sampleTimes, outputURLs) {
            do {
                frames.append(try extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            } catch where !slowSeek {
                logger.warning("Fast seek failed at \(time)s, using accurate seek for remaining frames: \(error.localizedDescription)")
                slowSeek = true
                frames.append(try extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            }
        }

        return frames
    }

    /// Seek time formatted like Go's `fmt.Sprint(float64)` (shortest round-trip representation).
    private func formatSeekTime(_ time: Double) -> String {
        "\(time)"
    }

    /// Output options matching stash's `ScreenshotTime` with BMP output.
    private func frameOutputArguments(outputPath: String) -> [String] {
        [
            "-frames:v", "1",
            "-vf", "scale=\(configuration.frameWidth):-2",
            "-c:v", "bmp",
            "-f", "rawvideo",
            outputPath
        ]
    }

    private func runFFmpegBatchExtraction(
        ffmpegPath: String,
        videoPath: String,
        sampleTimes: [Double],
        outputPaths: [String]
    ) throws {
        var arguments = ["-v", "error", "-y"]
        for time in sampleTimes {
            arguments += ["-ss", formatSeekTime(time), "-i", videoPath]
        }
        for (index, outputPath) in outputPaths.enumerated() {
            // `V` skips attached pictures (cover art), like ffmpeg's default stream selection.
            arguments += ["-map", "\(index):V:0"] + frameOutputArguments(outputPath: outputPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments

        try runCheckedFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg",
            exitFailureReason: "ffmpeg batch frame extraction",
            failureReason: HashError.frameExtractionFailed
        )
    }

    private func extractSingleFrame(
        ffmpegPath: String,
        videoPath: String,
        timestamp: Double,
        outputURL: URL,
        slowSeek: Bool
    ) throws -> RGBImage {
        let seek = ["-ss", formatSeekTime(timestamp)]
        var arguments = ["-v", "error", "-y"]
        arguments += slowSeek ? ["-i", videoPath] + seek : seek + ["-i", videoPath]
        arguments += frameOutputArguments(outputPath: outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments

        try? FileManager.default.removeItem(at: outputURL)
        try runCheckedFFmpegProcess(
            process,
            launchFailureReason: "Failed to launch ffmpeg",
            exitFailureReason: "ffmpeg",
            failureReason: HashError.frameExtractionFailed
        )
        return try BMPDecoder.decode(Data(contentsOf: outputURL))
    }

    private func runCheckedFFmpegProcess(
        _ process: Process,
        launchFailureReason: String,
        exitFailureReason: String,
        failureReason: (String) -> HashError
    ) throws {
        let (status, stderrOutput) = try runFFmpegProcess(
            process,
            launchFailureReason: launchFailureReason,
            failureReason: failureReason
        )
        guard status == 0 else {
            let message = stderrOutput.isEmpty ? "unknown ffmpeg error" : stderrOutput
            throw failureReason("\(exitFailureReason) exited with status \(status): \(message)")
        }
    }

    /// Runs an ffmpeg process, draining stderr to a temp file as it writes rather than
    /// buffering it in a `Pipe` and reading it back after `waitUntilExit()`. A `Pipe`'s
    /// kernel buffer is only ~64KB; a corrupt input can make ffmpeg log far more than that
    /// (thousands of "Invalid NAL unit size" lines even at `-v error`), so reading the pipe
    /// only after exit deadlocks: ffmpeg blocks on write() while nothing drains the pipe, and
    /// waitUntilExit() never returns.
    /// - Returns: The exit status and the trimmed stderr output
    private func runFFmpegProcess(
        _ process: Process,
        launchFailureReason: String,
        failureReason: (String) -> HashError
    ) throws -> (status: Int32, stderr: String) {
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
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? stderrHandle.close()
            throw failureReason("\(launchFailureReason): \(error.localizedDescription)")
        }
        try? stderrHandle.close()

        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        let stderrOutput = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stderrOutput)
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
