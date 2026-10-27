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
    private let extractionPolicy: FFmpegExtractionPolicy
    private let logger = Logger.phash

    init(configuration: HashConfiguration, extractionPolicy: FFmpegExtractionPolicy = .production) {
        self.extractionPolicy = extractionPolicy
        self.configuration = configuration
    }

    /// Extract frames from video for PHash generation
    /// - Parameters:
    ///   - asset: AVURLAsset for the video
    ///   - url: URL of the video file
    /// - Returns: Frames scaled to the configured width
    /// - Throws: HashError if frame extraction fails
    func extractFrames(from asset: AVURLAsset, url: URL) async throws -> [RGBImage] {
        let collection = try await extract(from: asset, url: url, composeSprite: false)
        return collection.frames
    }

    func extractSprite(from asset: AVURLAsset, url: URL) async throws -> RGBImage {
        let collection = try await extract(from: asset, url: url, composeSprite: true)
        return try collection.finishSprite()
    }

    private func extract(from asset: AVURLAsset, url: URL, composeSprite: Bool) async throws -> FrameCollection {
        try Task.checkCancellation()
        logger.debug("Extracting \(configuration.frameCount) frames from: \(url.path)")

        if configuration.useFFmpegFrameExtraction {
            let ffmpegPath = try resolveFFmpegPath()
            let durationSeconds = try await probeDuration(ffmpegPath: ffmpegPath, url: url, asset: asset)
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            logger.debug("Extracting frames at times: \(sampleTimes)")

            let frames = try await extractFramesWithFFmpeg(ffmpegPath: ffmpegPath, url: url, sampleTimes: sampleTimes, composeSprite: composeSprite)
            return frames
        } else {
            let durationSeconds = try await asset.load(.duration).seconds
            guard durationSeconds > 0 else {
                throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
            }
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            logger.debug("Extracting frames at times: \(sampleTimes)")

            return try await extractFramesWithAVFoundation(asset: asset, sampleTimes: sampleTimes, composeSprite: composeSprite)
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

    // MARK: - Duration

    /// Duration as videohashes sees it: the container duration reported by ffmpeg,
    /// rounded to 0.01s (stash rounds ffprobe's `format.duration` the same way).
    ///
    /// AVFoundation's duration can differ noticeably (e.g. 21.38s vs 21.43s), which
    /// shifts every sample timestamp, so it is only used when ffmpeg reports none.
    private func probeDuration(ffmpegPath: String, url: URL, asset: AVURLAsset) async throws -> Double {
        // ffmpeg exits non-zero here because no output is given; only stderr matters.
        let result = try await runFFmpegProcess(
            ffmpegPath: ffmpegPath,
            arguments: ["-hide_banner", "-i", url.path],
            launchFailureReason: "Failed to launch ffmpeg duration probe",
            failureReason: HashError.frameExtractionFailed
        )

        if let duration = result.reportedDuration, duration > 0 {
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
    /// Frames are first extracted in sequential groups of at most ten ffmpeg inputs
    /// by default (one seeked input and one BMP output per sample time). Each output
    /// uses the reference's per-frame options; the original unbounded group is kept
    /// for comparisons. If any group or BMP decoding fails,
    /// frames are extracted one process at a time with stash's fallback: fast seek
    /// first, then accurate seek for the remaining frames once a fast seek fails.
    private func extractFramesWithFFmpeg(ffmpegPath: String, url: URL, sampleTimes: [Double], composeSprite: Bool) async throws -> FrameCollection {
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
            for group in extractionPolicy.groups(count: sampleTimes.count) {
                try Task.checkCancellation()
                try await runFFmpegBatchExtraction(
                    ffmpegPath: ffmpegPath,
                    videoPath: url.path,
                    sampleTimes: Array(sampleTimes[group]),
                    outputPaths: outputURLs[group].map(\.path)
                )
            }
            var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
            for output in outputURLs {
                try Task.checkCancellation()
                collection.append(try BMPDecoder.decode(Data(contentsOf: output)))
            }
            return collection
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            logger.warning("Batch frame extraction failed, extracting frames one by one: \(error.localizedDescription)")
        }

        var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
        var slowSeek = false

        for (time, outputURL) in zip(sampleTimes, outputURLs) {
            try Task.checkCancellation()
            do {
                collection.append(try await extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            } catch where !slowSeek {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                logger.warning("Fast seek failed at \(time)s, using accurate seek for remaining frames: \(error.localizedDescription)")
                slowSeek = true
                collection.append(try await extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            }
        }

        return collection
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
    ) async throws {
        var arguments = ["-v", "error", "-y"]
        for time in sampleTimes {
            arguments += ["-ss", formatSeekTime(time), "-i", videoPath]
        }
        for (index, outputPath) in outputPaths.enumerated() {
            // `V` skips attached pictures (cover art), like ffmpeg's default stream selection.
            arguments += ["-map", "\(index):V:0"] + frameOutputArguments(outputPath: outputPath)
        }

        try await runCheckedFFmpegProcess(
            ffmpegPath: ffmpegPath,
            arguments: arguments,
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
    ) async throws -> RGBImage {
        let seek = ["-ss", formatSeekTime(timestamp)]
        var arguments = ["-v", "error", "-y"]
        arguments += slowSeek ? ["-i", videoPath] + seek : seek + ["-i", videoPath]
        arguments += frameOutputArguments(outputPath: outputURL.path)

        try? FileManager.default.removeItem(at: outputURL)
        try await runCheckedFFmpegProcess(
            ffmpegPath: ffmpegPath,
            arguments: arguments,
            launchFailureReason: "Failed to launch ffmpeg",
            exitFailureReason: "ffmpeg",
            failureReason: HashError.frameExtractionFailed
        )
        return try BMPDecoder.decode(Data(contentsOf: outputURL))
    }

    private func runCheckedFFmpegProcess(
        ffmpegPath: String,
        arguments: [String],
        launchFailureReason: String,
        exitFailureReason: String,
        failureReason: (String) -> HashError
    ) async throws {
        let result = try await runFFmpegProcess(
            ffmpegPath: ffmpegPath,
            arguments: arguments,
            launchFailureReason: launchFailureReason,
            failureReason: failureReason
        )
        guard result.status == 0 else {
            let message = result.stderr.isEmpty ? "unknown ffmpeg error" : result.stderr
            throw failureReason("\(exitFailureReason) exited with status \(result.status): \(message)")
        }
    }

    private func runFFmpegProcess(
        ffmpegPath: String,
        arguments: [String],
        launchFailureReason: String,
        failureReason: (String) -> HashError
    ) async throws -> FFmpegProcessResult {
        do {
            extractionPolicy.onLaunchAttempt?(arguments)
            return try await FFmpegProcessRunner().run(
                executableURL: URL(fileURLWithPath: ffmpegPath), arguments: arguments
            )
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw failureReason("\(launchFailureReason): \(error.localizedDescription)")
        }
    }

    private func resolveFFmpegPath() throws -> String {
        try FFmpegPathResolver().resolve(configuredPath: configuration.ffmpegPath)
    }

    // MARK: - AVFoundation fallback

    private func extractFramesWithAVFoundation(asset: AVURLAsset, sampleTimes: [Double], composeSprite: Bool) async throws -> FrameCollection {
        let timePoints = sampleTimes.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let imageGenerator = AVFrameGenerator(asset: asset, frameWidth: configuration.frameWidth)
        var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
        var successfulCount = 0
        var conversionError: (any Error)?

        for time in timePoints {
            try Task.checkCancellation()
            do {
                let image = try await imageGenerator.image(at: time)
                try Task.checkCancellation()
                successfulCount += 1
                if conversionError == nil {
                    do { collection.append(try RGBImage(cgImage: image)) }
                    catch { conversionError = error }
                }
                logger.trace("Extracted frame at \(time.seconds)s")
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                logger.warning("Failed to extract frame at \(time.seconds)s: \(error.localizedDescription)")
            }
        }

        try collection.normalizeAVFoundation(successfulCount: successfulCount, conversionError: conversionError)
        return collection
    }
}
