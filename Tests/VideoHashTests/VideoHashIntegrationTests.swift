import AVFoundation
import Darwin
import Synchronization
import Foundation
import Testing
@testable import VideoHash

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VIDEOHASH_FIXTURE_DIR"] != nil))
struct VideoHashIntegrationTests {
    private struct Fixture: Decodable {
        let file: String
        let phash: String
        let oshash: String
        let duration: Double
    }

    private func fixtures() throws -> [(URL, Fixture)] {
        let folder = try #require(ProcessInfo.processInfo.environment["VIDEOHASH_FIXTURE_DIR"])
        let manifest = try #require(Bundle.module.url(forResource: "video-hashes", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest)).map {
            (URL(fileURLWithPath: folder).appendingPathComponent($0.file), $0)
        }
    }

    @Test func testAllEntryPointsMatchBaseline() async throws {
        let generator = VideoHashGenerator()
        for (url, fixture) in try fixtures() {
            let result = try await generator.generateHashes(for: url)
            #expect(result.phash == fixture.phash)
            #expect(result.oshash == fixture.oshash)
            #expect(result.duration == fixture.duration)
            #expect(try await generator.generatePHash(for: url) == fixture.phash)
            #expect(try await generator.generateOSHash(for: url) == fixture.oshash)
        }
    }

    @Test func testConcurrentSingleCallsPreserveResults() async throws {
        let generator = VideoHashGenerator()
        let (url, fixture) = try #require(fixtures().first)
        async let first = generator.generateHashes(for: url)
        async let second = generator.generateHashes(for: url)
        for result in try await [first, second] {
            #expect(result.phash == fixture.phash)
            #expect(result.oshash == fixture.oshash)
        }
    }

    @Test func testBatchPreservesInputOrder() async throws {
        let entries = try fixtures().reversed()
        let results = try await VideoHashGenerator().generateHashes(for: entries.map(\.0), maxConcurrentTasks: 2)
        for (entry, result) in zip(entries, results) {
            #expect(result.phash == entry.1.phash)
            #expect(result.oshash == entry.1.oshash)
        }
    }
    @Test func testStreamContinuesAfterFileFails() async throws {
        let (url, fixture) = try #require(fixtures().first)
        let missing = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let stream = await VideoHashGenerator().generateHashesStream(for: [url, missing, url], maxConcurrentTasks: 1)
        var iterator = stream.makeAsyncIterator()
        let first = try #require(try await iterator.next())
        #expect(first.index == 0)
        #expect(first.url == url)
        #expect(try first.result.get().phash == fixture.phash)
        let failed = try #require(try await iterator.next())
        #expect(failed.index == 1)
        #expect(failed.url == missing)
        #expect(throws: HashError.fileNotFound(path: missing.path)) {
            try failed.result.get()
        }
        let last = try #require(try await iterator.next())
        #expect(last.index == 2)
        #expect(try last.result.get().phash == fixture.phash)
        let end = try await iterator.next()
        #expect(end == nil)
    }

    @Test func testStreamAssociatesEveryResultWithItsInput() async throws {
        let entries = try fixtures()
        let stream = await VideoHashGenerator().generateHashesStream(for: entries.map(\.0), maxConcurrentTasks: 2)
        var received = Set<Int>()
        for try await (index, url, result) in stream {
            #expect(received.insert(index).inserted)
            #expect(url == entries[index].0)
            #expect(try result.get().phash == entries[index].1.phash)
            #expect(try result.get().oshash == entries[index].1.oshash)
        }
        #expect(received.count == entries.count)
    }

    @Test func testAVFoundationBridgePreservesPixels() async throws {
        for (url, _) in try fixtures() {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let original = AVAssetImageGenerator(asset: asset)
            original.appliesPreferredTrackTransform = true
            original.requestedTimeToleranceBefore = .positiveInfinity
            original.requestedTimeToleranceAfter = .positiveInfinity
            original.maximumSize = CGSize(width: 160, height: 10_000)
            let bridge = AVFrameGenerator(asset: asset, frameWidth: 160)
            for index in 0..<25 {
                let time = CMTime(seconds: 0.05 * duration + Double(index) * (0.9 * duration / 25), preferredTimescale: 600)
                let (expected, _) = try await original.image(at: time)
                let actual = try await bridge.image(at: time)
                #expect(try RGBImage(cgImage: actual) == RGBImage(cgImage: expected))
            }
        }
    }

    @Test func testAVFoundationCancellationAfterSubmission() async throws {
        let (url, _) = try #require(fixtures().first)
        let handle = Mutex<Task<CGImage, any Error>?>(nil)
        let gate = AsyncStream<Void>.makeStream()
        let bridge = AVFrameGenerator(asset: AVURLAsset(url: url), frameWidth: 160) {
            handle.withLock { $0?.cancel() }
        }
        let task = Task {
            for await _ in gate.stream { break }
            return try await bridge.image(at: CMTime(seconds: 100, preferredTimescale: 600))
        }
        handle.withLock { $0 = task }
        gate.continuation.yield(())
        gate.continuation.finish()
        defer { task.cancel(); handle.withLock { $0 = nil } }
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: task) {}
        }
    }

    @Test func testCancelledBatchStopsActiveChildren() async throws {
        let entries = Array(try fixtures().prefix(2))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("ffmpeg")
        let quotedRoot = "'" + root.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        #!/bin/sh
        if [ "$1" = '-hide_banner' ]; then
            echo 'Duration: 00:01:00.00' >&2
            exit 1
        fi
        for last; do :; done
        printf '%s\\n%s' "$$" "$last" > \(quotedRoot)/$$.ready
        while :; do :; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let generator = VideoHashGenerator(configuration: HashConfiguration(ffmpegPath: executable.path))
        let task = Task { try await generator.generateHashes(for: entries.map(\.0), maxConcurrentTasks: 2) }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var markers: [URL] = []
        while markers.count < 2 {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "Batch children not ready", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
            markers = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "ready" }
        }
        let outputs = try markers.map { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
        let pids = try outputs.map { try #require(Int32($0[0])) }
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                for pid in pids { kill(pid, SIGKILL) }
            } catch {}
        }
        defer { watchdog.cancel() }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: task) { for pid in pids { kill(pid, SIGKILL) } }
        }
        for pid in pids { #expect(kill(pid, 0) == -1 && errno == ESRCH) }
        for output in outputs {
            let directory = URL(fileURLWithPath: output[1]).deletingLastPathComponent()
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "ready" }.count == 2)
    }

}
