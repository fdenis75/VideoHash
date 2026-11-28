import AVFoundation
import Foundation
import Testing
@testable import VideoHash

/// Containers and codecs AVFoundation cannot open, hashed through ffmpeg.
@Suite(.serialized, .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")))
struct FFmpegFallbackTests {
    private static let ffmpeg = "/opt/homebrew/bin/ffmpeg"
    private let configuration = HashConfiguration(ffmpegPath: ffmpeg)

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func runFFmpeg(_ arguments: [String], output: URL) async throws {
        let result = try await FFmpegProcessRunner().run(
            executableURL: URL(fileURLWithPath: Self.ffmpeg), arguments: ["-v", "error", "-y"] + arguments + [output.path]
        )
        try #require(result.status == 0, "\(result.stderr)")
    }

    /// Ten seconds of test pattern, large enough for OSHash.
    private func makeVideo(_ name: String, codec: String, in root: URL) async throws -> URL {
        let url = root.appendingPathComponent(name)
        try await runFFmpeg(
            ["-f", "lavfi", "-i", "testsrc=duration=10:size=320x240:rate=25",
             "-c:v", codec, "-b:v", "1M", "-bf", "0", "-pix_fmt", "yuv420p"],
            output: url
        )
        return url
    }

    private func hasAVFoundationVideo(_ url: URL) async -> Bool {
        let tracks = try? await AVURLAsset(url: url).load(.tracks)
        return tracks?.contains { $0.mediaType == .video } ?? false
    }

    private func expectInvalidVideo(_ operation: () async throws -> Void) async {
        let error = await #expect(throws: HashError.self) { try await operation() }
        guard case .invalidVideoFile = error else {
            Issue.record("Expected invalidVideoFile, got \(String(describing: error))")
            return
        }
    }

    @Test(arguments: [("clip.wmv", "wmv2"), ("clip.mkv", "libx264")], [true, false])
    func testSingleFileEntryPoints(video: (name: String, codec: String), useFFmpeg: Bool) async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try await makeVideo(video.name, codec: video.codec, in: root)
        #expect(await !hasAVFoundationVideo(url), "fixture must exercise the fallback")
        var configuration = configuration
        configuration.useFFmpegFrameExtraction = useFFmpeg
        let generator = VideoHashGenerator(configuration: configuration)

        let result = try await generator.generateHashes(for: url)
        #expect(result.duration == 10)
        #expect(!result.phash.isEmpty && result.phash != "0")
        #expect(result.oshash.count == 16)
        #expect(try await generator.generatePHash(for: url) == result.phash)
        #expect(try await generator.generateOSHash(for: url) == result.oshash)
    }

    @Test func testRemuxedMKVMatchesMP4() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mp4 = try await makeVideo("clip.mp4", codec: "libx264", in: root)
        let mkv = root.appendingPathComponent("clip.mkv")
        try await runFFmpeg(["-i", mp4.path, "-c", "copy"], output: mkv)
        #expect(await hasAVFoundationVideo(mp4))
        #expect(await !hasAVFoundationVideo(mkv))
        let generator = VideoHashGenerator(configuration: configuration)

        let native = try await generator.generateHashes(for: mp4)
        let fallback = try await generator.generateHashes(for: mkv)
        #expect(native.phash == fallback.phash)
        #expect(native.duration == fallback.duration)
    }

    @Test func testBatchAndStream() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wmv = try await makeVideo("clip.wmv", codec: "wmv2", in: root)
        let mkv = try await makeVideo("clip.mkv", codec: "libx264", in: root)
        let text = root.appendingPathComponent("notes.txt")
        try Data(String(repeating: "not a video\n", count: 20_000).utf8).write(to: text)
        let generator = VideoHashGenerator(configuration: configuration)

        let batch = try await generator.generateHashes(for: [wmv, mkv], maxConcurrentTasks: 2)
        #expect(batch.map(\.duration) == [10, 10])

        var outcomes: [Int: Result<HashResult, any Error>] = [:]
        for try await (index, _, result) in await generator.generateHashesStream(for: [wmv, text, mkv], maxConcurrentTasks: 2) {
            outcomes[index] = result
        }
        #expect(try outcomes[0]?.get().phash == batch[0].phash)
        #expect(try outcomes[2]?.get().phash == batch[1].phash)
        let failed = try #require(outcomes[1])
        await expectInvalidVideo { _ = try failed.get() }
    }

    /// ffmpeg opens all of these, but none is a video.
    @Test(arguments: ["notes.txt", "garbage.bin", "garbage.mkv", "still.png", "audio.mka", "cover.mp3"])
    func testNotAVideoThrows(name: String) async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(name)
        let tone = ["-f", "lavfi", "-i", "sine=duration=10"]
        let picture = ["-f", "lavfi", "-i", "testsrc=size=320x240"]
        switch name {
        case "still.png":
            try await runFFmpeg(picture + ["-frames:v", "1"], output: url)
        case "audio.mka":
            try await runFFmpeg(tone, output: url)
        case "cover.mp3":
            try await runFFmpeg(
                tone + picture + ["-map", "0", "-map", "1", "-frames:v", "1", "-c:v", "png", "-disposition:v", "attached_pic"],
                output: url
            )
        default:
            try Data(String(repeating: "not a video\n", count: 20_000).utf8).write(to: url)
        }
        let generator = VideoHashGenerator(configuration: configuration)
        await expectInvalidVideo { _ = try await generator.generateHashes(for: url) }
        await expectInvalidVideo { _ = try await generator.generatePHash(for: url) }
    }

    @Test func testUnavailableFFmpegThrowsInvalidVideo() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try await makeVideo("clip.wmv", codec: "wmv2", in: root)
        let generator = VideoHashGenerator(configuration: HashConfiguration(ffmpegPath: "/videohash-missing-ffmpeg"))
        await expectInvalidVideo { _ = try await generator.generateHashes(for: url) }
        await expectInvalidVideo { _ = try await generator.generatePHash(for: url) }
    }
}
