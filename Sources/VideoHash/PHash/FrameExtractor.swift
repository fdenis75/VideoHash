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
import os

/// Extracts frames from video files for PHash generation.
actor FrameExtractor: Sendable {
    private let configuration: HashConfiguration
    private let extractionPolicy: FFmpegExtractionPolicy
    private let logger = Logger.videoHash
    private let signposter = OSSignposter(subsystem: "com.videohash", category: "PHash")
    
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
    
    func extractSprite(from asset: AVURLAsset, url: URL, signpost: OSSignpostID? = nil) async throws -> RGBImage {
        let signpostID = signpost ?? signposter.makeSignpostID()
        let collection = try await extract(from: asset, url: url, composeSprite: true, signpost: signpostID)
        return try collection.finishSprite()
    }
    
    private func extract(from asset: AVURLAsset, url: URL, composeSprite: Bool, signpost: OSSignpostID? = nil) async throws -> FrameCollection {
        let signpostID = signpost ?? signposter.makeSignpostID()
        try Task.checkCancellation()
        logger.debug("Extracting \(configuration.frameCount) frames from: \(url.path)")
        
        if configuration.useFFmpegFrameExtraction {
            let resolveState = signposter.beginInterval("ffmpegresolvePath", id: signpostID, "URL: \(url.lastPathComponent)")
            
            let ffmpegPath = try resolveFFmpegPath()
            signposter.endInterval("ffmpegresolvePath", resolveState)
            let probingState = signposter.beginInterval("probeDuration", id: signpostID, "URL: \(url.lastPathComponent)")
            let durationSeconds = try await probeDuration(ffmpegPath: ffmpegPath, url: url, asset: asset)
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            signposter.endInterval("probeDuration", probingState)
            logger.debug("Extracting frames at times: \(sampleTimes)")
            
            let frames = try await extractFramesWithFFmpeg(ffmpegPath: ffmpegPath, url: url, sampleTimes: sampleTimes, composeSprite: composeSprite, signpost: signpostID)
            return frames
        } else {
            
            signposter.emitEvent("SwitchingToAvFoundation", id: signpostID)
            let state = signposter.beginInterval("runAvFoundationBatchExtraction", id: signpostID, "URL: \(url.lastPathComponent)")
            defer { signposter.endInterval("runAvFoundationBatchExtraction", state) }
            let nativeAsset = configuration.avFoundationAlignsFrameSelection
                ? AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]) : asset
            let assetDuration = try await nativeAsset.load(.duration).seconds
            let durationSeconds = configuration.avFoundationAlignsFrameSelection
                ? (assetDuration * 100).rounded() / 100 : assetDuration
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw HashError.invalidVideoFile(path: url.path, reason: "Video has zero duration")
            }
            let sampleTimes = try makeSampleTimes(durationSeconds: durationSeconds)
            logger.debug("Extracting frames at times: \(sampleTimes)")
            
            return try await extractFramesWithAVFoundation(asset: nativeAsset, sampleTimes: sampleTimes, composeSprite: composeSprite)
        }
    }
    
    
    private func diagnosticDirectory(for source: URL, backend: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = "\(source.lastPathComponent)-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))-\(backend)"
        return (configuration.frameTimingDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent(name)
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
    /// for comparisons. Unsupported scaler conversions abort the current request.
    /// For other group or BMP decoding failures, frames are extracted one process
    /// at a time with stash's fallback: fast seek first, then accurate seek for the
    /// remaining frames once a fast seek fails.
    private func extractFramesWithFFmpeg(ffmpegPath: String, url: URL, sampleTimes: [Double], composeSprite: Bool, signpost: OSSignpostID? = nil) async throws -> FrameCollection {
        let fileManager = FileManager.default
        let tempDirectory = diagnosticDirectory(for: url, backend: "ffmpg")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        logger.info("temp dir for ffmpe : \(tempDirectory.path())for \(url.path())")
        defer {
            if configuration.frameTimingDirectory == nil {
                try? fileManager.removeItem(at: tempDirectory)
            }
        }
        
        
        if configuration.frameTimingDirectory != nil {
            try url.path.write(to: tempDirectory.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
            try (configuration.frameTimingRunID ?? "").write(to: tempDirectory.appendingPathComponent("run.txt"), atomically: true, encoding: .utf8)
        }
        let outputURLs = sampleTimes.indices.map {
            tempDirectory.appendingPathComponent("frame-\($0).bmp")
        }
        if configuration.frameTimingDirectory != nil {
            let rows = zip(sampleTimes.indices, sampleTimes).map { "\($0),\($1)" }
            try (["sample_index,requested_seconds"] + rows).joined(separator: "\n").write(
                to: tempDirectory.appendingPathComponent("requests.csv"), atomically: true, encoding: .utf8)
        }
        let signpostID = signpost ?? signposter.makeSignpostID()
        do {
            for group in extractionPolicy.groups(count: sampleTimes.count) {
                try Task.checkCancellation()
                //let signpostID = signposter.makeSignpostID()
                signposter.emitEvent("runFFmpegBatchExtractionStarted", id: signpostID)
                let state = signposter.beginInterval("runFFmpegBatchExtraction", id: signpostID, "URL: \(url.lastPathComponent) Frames: \(group.count)")
                defer { signposter.endInterval("runFFmpegBatchExtraction", state) }
                try await runFFmpegBatchExtraction(
                    ffmpegPath: ffmpegPath,
                    videoPath: url.path,
                    sampleTimes: Array(sampleTimes[group]),
                    outputPaths: outputURLs[group].map(\.path)
                )
            }
            // let collectionID = signposter.makeSignpostID()
            signposter.emitEvent("frameCollectionStarted", id: signpostID)
            let collectionState = signposter.beginInterval("frameCollection", id: signpostID,"URL: \(url.lastPathComponent)")
            defer { signposter.endInterval("frameCollection", collectionState) }
            var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
            for output in outputURLs {
                try Task.checkCancellation()
                collection.append(try BMPDecoder.decode(Data(contentsOf: output)))
            }
            return collection
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            if Self.isUnsupportedConversion(error) { throw error }
            logger.warning("Batch frame extraction failed, extracting frames one by one: \(error.localizedDescription)")
        }
        signposter.emitEvent("Switching to slow mode", id: signpostID)
        // Lets a batch start another file meanwhile (`SlowPathAwareScheduler`).
        SlowExtraction.began()
        var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
        var slowSeek = false
        let collectionState2 = signposter.beginInterval("frameCollectionSlow", id: signpostID,"URL: \(url.lastPathComponent)")
        defer { signposter.endInterval("frameCollectionSlow", collectionState2) }
        for (time, outputURL) in zip(sampleTimes, outputURLs) {
            try Task.checkCancellation()
            do {
                collection.append(try await extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            } catch where !slowSeek {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                if Self.isUnsupportedConversion(error) { throw error }
                logger.warning("Fast seek failed at \(time)s, using accurate seek for remaining frames: \(error.localizedDescription)")
                slowSeek = true
                collection.append(try await extractSingleFrame(
                    ffmpegPath: ffmpegPath, videoPath: url.path, timestamp: time, outputURL: outputURL, slowSeek: slowSeek
                ))
            }
        }
        
        return collection
    }
    
    /// Seeking again cannot repair a conversion that libswscale does not support.
    private static func isUnsupportedConversion(_ error: any Error) -> Bool {
        guard let hashError = error as? HashError,
              case .frameExtractionFailed(let reason) = hashError else { return false }
        return reason.split(separator: "\n").contains { line in
            line.contains("[swscaler") && line.contains("Unsupported input (Operation not supported)")
        }
    }
    
    /// Seek time formatted like Go's `fmt.Sprint(float64)` (shortest round-trip representation).
    private func formatSeekTime(_ time: Double) -> String {
        "\(time)"
    }
    
    /// Output options matching stash's `ScreenshotTime` with BMP output.
    private func frameOutputArguments(outputPath: String, timestamp: Double? = nil) -> [String] {
        var filter = "scale=\(configuration.frameWidth):-2"
        if configuration.frameTimingDirectory != nil, let timestamp {
            filter += ",trim=start=\(timestamp)"
        }
        return (configuration.frameTimingDirectory == nil ? [] : [
            "-fps_mode", "passthrough", "-enc_time_base", "filter",
            "-stats_enc_pre", outputPath + ".timing.csv",
            "-stats_enc_pre_fmt", "{n},{pts},{tb},{ptsi},{tbi}"
        ]) + [
            "-frames:v", "1",
            "-vf", filter,
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
        var arguments = ["-v", "error", "-y", "-hwaccel", "videotoolbox"]
        if configuration.frameTimingDirectory != nil {
            arguments += ["-copyts", "-start_at_zero"]
        }
        //  var arguments = ["-v", "error", "-y"]
        for time in sampleTimes {
            arguments += ["-ss", formatSeekTime(time), "-i", videoPath]
        }
        for (index, outputPath) in outputPaths.enumerated() {
            // `V` skips attached pictures (cover art), like ffmpeg's default stream selection.
            arguments += ["-map", "\(index):V:0"] + frameOutputArguments(outputPath: outputPath, timestamp: sampleTimes[index])
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
        if configuration.frameTimingDirectory != nil {
            arguments += ["-copyts", "-start_at_zero"]
            // In the slow path trim in the filter, before encoding, rather than after it.
            arguments += slowSeek ? ["-i", videoPath] : seek + ["-i", videoPath]
            arguments += ["-map", "0:V:0"]
        } else {
            arguments += slowSeek ? ["-i", videoPath] + seek : seek + ["-i", videoPath]
        }
        arguments += frameOutputArguments(outputPath: outputURL.path, timestamp: timestamp)
        
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
        let fileManager = FileManager.default
        let tempDirectory = diagnosticDirectory(for: asset.url, backend: "avf")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            if configuration.frameTimingDirectory == nil {
                do { try fileManager.removeItem(at: tempDirectory) }
                catch { logger.warning("Failed to remove temporary frames at \(tempDirectory.path): \(error)") }
            }
        }
        logger.info("Saving temporary AVFoundation frames to: \(tempDirectory.path) for \(asset.url.path())")

        if configuration.frameTimingDirectory != nil {
            try asset.url.path.write(to: tempDirectory.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
            try (configuration.frameTimingRunID ?? "").write(to: tempDirectory.appendingPathComponent("run.txt"), atomically: true, encoding: .utf8)
        }
        let timePoints: [CMTime]
        if configuration.avFoundationAlignsFrameSelection,
           let selected = try await AVFoundationFrameSampler.firstPresentationTimes(atOrAfter: sampleTimes, in: asset) {
            timePoints = selected
        } else {
            if configuration.avFoundationAlignsFrameSelection {
                logger.warning("Sample cursors unavailable for \(asset.url.path); using requested times without frame alignment")
            }
            timePoints = sampleTimes.map { CMTime(seconds: $0, preferredTimescale: 600) }
        }
       
        
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: configuration.frameWidth, height: 10_000)
        
        
        //   AVFrameGenerator(asset: asset, frameWidth: configuration.frameWidth)
        
        var collection = FrameCollection(configuration: configuration, composeSprite: composeSprite)
        var successfulCount = 0
        var conversionError: (any Error)?
        
        var timestampRows = ["sample_index,filename,requested_value,requested_timescale,requested_seconds,actual_value,actual_timescale,actual_seconds,delta_seconds,planned_seconds"]
        let timestampsURL = tempDirectory.appendingPathComponent("timestamps.csv")

        for (index, requested) in timePoints.enumerated() {
            try Task.checkCancellation()
            let image: CGImage
            let actual: CMTime
            do {
                (image, actual) = try await generator.image(at: requested)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                logger.warning("Failed to extract frame at \(requested.seconds)s: \(error.localizedDescription)")
                continue
            }
            try Task.checkCancellation()
            successfulCount += 1
            if conversionError == nil {
                do {
                    let frame = try RGBImage(cgImage: image, preserveSourceColorSpace: configuration.avFoundationPreservesSourceColorSpace)
                    let filename = String(format: "frame-%03d.bmp", successfulCount)
                    try frame.bmpData().write(to: tempDirectory.appendingPathComponent(filename))
                    collection.append(frame)
                    let delta = CMTimeSubtract(actual, requested).seconds
                    timestampRows.append("\(index),\(filename),\(requested.value),\(requested.timescale),\(requested.seconds),\(actual.value),\(actual.timescale),\(actual.seconds),\(delta),\(sampleTimes[index])")
                    try (timestampRows.joined(separator: "\n") + "\n").write(to: timestampsURL, atomically: true, encoding: .utf8)
                } catch {
                    conversionError = error
                }
            }
            logger.debug("Extracted frame \(index): requested=\(requested.seconds)s, actual=\(actual.seconds)s")
        }

            try collection.normalizeAVFoundation(successfulCount: successfulCount, conversionError: conversionError)
            return collection
        }
    
}
