import AVFoundation
import Darwin
import Foundation
import Testing
@testable import VideoHash

@Suite(.serialized)
struct FrameExtractionCancellationTests {
    @Test func testPreCancelledPublicCalls() async throws {
        let url = URL(fileURLWithPath: "/nonexistent-videohash-cancellation-fixture")
        for kind in 0..<4 {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                let generator = VideoHashGenerator()
                switch kind {
                case 0: _ = try await generator.generateHashes(for: url)
                case 1: _ = try await generator.generatePHash(for: url)
                case 2: _ = try await generator.generateOSHash(for: url)
                default: _ = try await OSHashGenerator().generateHash(for: url)
                }
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test func testCancelledExtractionDoesNotEnterFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("ffmpeg")
        let ready = root.appendingPathComponent("ready")
        let calls = root.appendingPathComponent("calls")
        let pidFile = root.appendingPathComponent("pid")
        func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        echo called >> \(quote(calls.path))
        if [ "$1" = '-hide_banner' ]; then
            echo 'Duration: 00:01:00.00' >&2
            exit 1
        fi
        for last; do :; done
        echo $$ > \(quote(pidFile.path))
        printf '%s' "$last" > \(quote(ready.path))
        while :; do :; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = HashConfiguration(ffmpegPath: executable.path)
        let url = root.appendingPathComponent("unused.mp4")
        let task = Task {
            try await FrameExtractor(configuration: configuration).extractFrames(from: AVURLAsset(url: url), url: url)
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: ready.path) {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "Fixture not ready", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
        let output = try String(contentsOf: ready, encoding: .utf8)
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                kill(pid, SIGKILL)
            } catch {}
        }
        defer { watchdog.cancel() }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: task) { kill(pid, SIGKILL) }
        }
        let callCount = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").count
        // One duration probe and up to three concurrent extraction batches.
        #expect((2...4).contains(callCount))
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: output).deletingLastPathComponent().path))
    }
    @Test func testAVFoundationPreCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let asset = AVURLAsset(url: URL(fileURLWithPath: "/missing-video"))
            return try await AVFrameGenerator(asset: asset, frameWidth: 160).image(at: .zero)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

}
