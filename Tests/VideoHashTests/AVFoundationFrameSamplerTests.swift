import AVFoundation
import Foundation
import Testing
@testable import VideoHash

@Suite(.enabled(if: ProcessInfo.processInfo.environment["VIDEOHASH_RUN_MEDIA_TESTS"] == "1"))
struct AVFoundationFrameSamplerTests {
    @Test("Sample cursor selects the next real presentation frame, including variable-rate gaps", arguments: [false, true])
    func testPresentationFrameSelection(variableRate: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("frames.mp4")
        let executable = try FFmpegPathResolver().resolve(configuredPath: nil)
        var args = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=64x48:rate=10:duration=2"]
        if variableRate { args += ["-vf", "select=lt(n\\,10)+not(mod(n\\,3))", "-fps_mode", "vfr"] }
        args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", url.path]
        let result = try await FFmpegProcessRunner().run(executableURL: URL(fileURLWithPath: executable), arguments: args)
        #expect(result.status == 0, "\(result.stderr)")
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let selected = try #require(await AVFoundationFrameSampler.firstPresentationTimes(
            atOrAfter: [0, 0.15, 0.9, 0.91, 1.1, 1.21, 1.8], in: asset))
        let expected = variableRate ? [0.0, 0.2, 0.9, 1.2, 1.2, 1.5, 1.8] : [0.0, 0.2, 0.9, 1.0, 1.1, 1.3, 1.8]
        #expect(selected.count == expected.count)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for (time, expectedTime) in zip(selected, expected) {
            #expect(abs(time.seconds - expectedTime) < 0.000001)
            let (_, actual) = try await generator.image(at: time)
            #expect(CMTimeCompare(time, actual) == 0)
        }
        // A deliberately unusable FFmpeg path proves native hashing does not consult FFmpeg.
        let configuration = HashConfiguration(useFFmpegFrameExtraction: false, ffmpegPath: "/nonexistent/native-must-not-use-ffmpeg")
        let nativeHash = try await PHashGenerator(configuration: configuration).generateHash(for: url)
        #expect(UInt64(nativeHash, radix: 16) != nil)

    }
}
