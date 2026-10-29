import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import VideoHash

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VIDEOHASH_FIXTURE_DIR"] != nil))
struct FrameExtractionParityTests {
    private struct Fixture: Decodable {
        let file: String
    }

    private func urls() throws -> [URL] {
        let folder = try #require(ProcessInfo.processInfo.environment["VIDEOHASH_FIXTURE_DIR"])
        let manifest = try #require(Bundle.module.url(forResource: "video-hashes", withExtension: "json", subdirectory: "Fixtures"))
        // Additional regression videos must not silently change the accepted corpus.
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest)).map {
            URL(fileURLWithPath: folder).appendingPathComponent($0.file)
        }
    }

    @Test(arguments: [true, false])
    func testStreamingMatchesFrameArray(useFFmpeg: Bool) async throws {
        let configuration = HashConfiguration(useFFmpegFrameExtraction: useFFmpeg)
        for url in try urls() {
            let asset = AVURLAsset(url: url)
            let extractor = FrameExtractor(configuration: configuration)
            let frames: [RGBImage]
            if useFFmpeg { frames = try await extractor.extractFrames(from: asset, url: url) }
            else { frames = try await legacyAVFoundationFrames(asset, configuration: configuration) }
            let expected = try SpriteComposer(configuration: configuration).composeSprite(from: frames)
            let actual = try await extractor.extractSprite(from: asset, url: url)
            #expect(actual == expected, "Pixel parity for \(url.lastPathComponent), ffmpeg=\(useFFmpeg)")
        }
    }
    @Test func testGroupedInputsPreserveEveryDecodedPixel() async throws {
        for url in try urls() {
            try await checkGroupedPixels(url)
        }
    }

    private func checkGroupedPixels(_ url: URL) async throws {
        let configuration = HashConfiguration.default
        let asset = AVURLAsset(url: url)
        let originalTrace = Mutex<[[String]]>([])
        var originalPolicy = FFmpegExtractionPolicy()
        originalPolicy.onLaunchAttempt = { arguments in originalTrace.withLock { $0.append(arguments) } }
        let expected = try await FrameExtractor(configuration: configuration, extractionPolicy: originalPolicy).extractFrames(from: asset, url: url)
        let referenceCommands = originalTrace.withLock { $0 }
        #expect(referenceCommands.count == 2, "Reference must succeed without fallback")
        let originalBatch = try #require(referenceCommands.dropFirst().first)
        let times = originalBatch.indices.filter { originalBatch[$0] == "-ss" }.map { originalBatch[$0 + 1] }
        #expect(times.count == 25)
        for limit in [1, 5, 10] {
            let trace = Mutex<[[String]]>([])
            var policy = try FFmpegExtractionPolicy(maxInputsPerProcess: limit)
            policy.onLaunchAttempt = { arguments in trace.withLock { $0.append(arguments) } }
            let candidate = FrameExtractor(configuration: configuration, extractionPolicy: policy)
            let actual = try await candidate.extractFrames(from: asset, url: url)
            #expect(actual == expected, "Frame pixels for \(url.lastPathComponent), input limit \(limit)")
            let commands = trace.withLock { $0 }
            let groups = policy.groups(count: 25)
            #expect(commands.count == 1 + groups.count, "No hidden fallback")
            for (group, command) in zip(groups, commands.dropFirst()) {
                var expectedArguments = ["-v", "error", "-y"]
                for index in group { expectedArguments += ["-ss", times[index], "-i", url.path] }
                let outputs = command.filter { $0.hasSuffix(".bmp") }
                #expect(outputs.count == group.count)
                for (local, global) in group.enumerated() {
                    let output = try #require(outputs.first { URL(fileURLWithPath: $0).lastPathComponent == "frame-\(global).bmp" })
                    expectedArguments += ["-map", "\(local):V:0", "-frames:v", "1", "-vf", "scale=160:-2", "-c:v", "bmp", "-f", "rawvideo", output]
                }
                #expect(command == expectedArguments)
            }
        }
    }

    @Test func testGroupedInputsPreserveGeneratedEdgeFixtures() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ffmpeg = try FFmpegPathResolver().resolve(configuredPath: nil)
        func run(_ arguments: [String]) async throws {
            let result = try await FFmpegProcessRunner().run(executableURL: URL(fileURLWithPath: ffmpeg), arguments: ["-v", "error", "-y"] + arguments)
            guard result.status == 0 else { throw HashError.processingFailed(reason: result.stderr) }
        }
        let landscape = root.appendingPathComponent("landscape.mp4")
        let portrait = root.appendingPathComponent("portrait.mp4")
        let vfr = root.appendingPathComponent("vfr.mp4")
        let multi = root.appendingPathComponent("multi.mp4")
        let cover = root.appendingPathComponent("cover.jpg")
        let attached = root.appendingPathComponent("attached.mp4")
        try await run(["-f", "lavfi", "-i", "testsrc2=size=64x48:rate=12:duration=2", "-c:v", "libx264", landscape.path])
        try await run(["-f", "lavfi", "-i", "testsrc2=size=48x80:rate=12:duration=2", "-c:v", "libx264", portrait.path])
        try await run(["-i", landscape.path, "-vf", "select='lt(n,12)+not(mod(n,3))'", "-fps_mode", "vfr", "-c:v", "libx264", vfr.path])
        try await run(["-i", landscape.path, "-i", portrait.path, "-map", "0:v", "-map", "1:v", "-c", "copy", multi.path])
        try await run(["-f", "lavfi", "-i", "color=red:size=16x16", "-frames:v", "1", cover.path])
        try await run(["-i", landscape.path, "-i", cover.path, "-map", "0:v", "-map", "1:v", "-c", "copy", "-disposition:v:1", "attached_pic", attached.path])
        for url in [portrait, vfr, multi, attached] { try await checkGroupedPixels(url) }
    }

    // Frozen collect-normalize-convert order from before streaming extraction.
    private func legacyAVFoundationFrames(_ asset: AVURLAsset, configuration: HashConfiguration) async throws -> [RGBImage] {
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        generator.maximumSize = CGSize(width: configuration.frameWidth, height: 10_000)
        var images: [CGImage] = []
        for index in 0..<configuration.frameCount {
            let seconds = 0.05 * duration + Double(index) * (0.9 * duration / Double(configuration.frameCount))
            do {
                let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                images.append(image)
            } catch {
                try Task.checkCancellation()
            }
        }
        guard images.count >= configuration.frameCount / 2 else {
            throw HashError.insufficientFrames(expected: configuration.frameCount, actual: images.count)
        }
        while images.count < configuration.frameCount {
            guard let last = images.last else { throw HashError.insufficientFrames(expected: configuration.frameCount, actual: images.count) }
            images.append(last)
        }
        return try images.map { try RGBImage(cgImage: $0) }
    }

}
