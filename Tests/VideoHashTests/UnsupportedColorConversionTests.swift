import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import VideoHash

struct UnsupportedColorConversionTests {
    @Test(arguments: [true, false])
    func testUnsupportedConversionAbortsWithoutSeekRetries(failsInBatch: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("ffmpeg")
        let calls = root.appendingPathComponent("calls")
        let outputRecord = root.appendingPathComponent("output")
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let diagnostic = "[swscaler @ 0x1] Unsupported input (Operation not supported): fmt:yuv420p csp:bt709 prim:reserved trc:reserved -> fmt:bgr24 csp:gbr prim:reserved trc:reserved"
        let script = """
        #!/bin/sh
        if [ "$1" = '-hide_banner' ]; then
            echo probe >> \(quote(calls.path))
            echo 'Duration: 00:01:00.00' >&2
            exit 1
        fi
        mode=fast; input=0
        for arg; do
            [ "$arg" = '-i' ] && input=1
            if [ "$arg" = '-ss' ] && [ "$input" = 1 ]; then mode=slow; fi
            if [ "$arg" = '-map' ]; then mode=batch; fi
        done
        for last; do :; done
        printf '%s' "$last" > \(quote(outputRecord.path))
        echo "$mode" >> \(quote(calls.path))
        if [ "$mode" = batch ] && [ '\(failsInBatch)' = false ]; then
            echo 'Ordinary seek error' >&2
        else
            echo \(quote(diagnostic)) >&2
        fi
        exit 211
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = HashConfiguration(ffmpegPath: executable.path)
        let video = root.appendingPathComponent("unused.mp4")
        do {
            _ = try await FrameExtractor(configuration: configuration).extractSprite(from: AVURLAsset(url: video), url: video)
            Issue.record("Unsupported colour conversion must fail")
        } catch let error as HashError {
            guard case .frameExtractionFailed(let reason) = error else { throw error }
            #expect(reason.contains(diagnostic))
        }
        let actual = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(actual == (failsInBatch ? ["probe", "batch"] : ["probe", "batch", "fast"]))
        let output = try String(contentsOf: outputRecord, encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: output).deletingLastPathComponent().path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIDEOHASH_ERROR_FIXTURE"] != nil))
    func testRealUnsupportedColorVideoAbortsBeforeFallback() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["VIDEOHASH_ERROR_FIXTURE"])
        let url = URL(fileURLWithPath: path)
        let commands = Mutex<[[String]]>([])
        var policy = FFmpegExtractionPolicy.production
        policy.onLaunchAttempt = { arguments in commands.withLock { $0.append(arguments) } }
        let extractor = FrameExtractor(configuration: .default, extractionPolicy: policy)
        do {
            _ = try await extractor.extractSprite(from: AVURLAsset(url: url), url: url)
            Issue.record("Expected the supplied fixture to have an unsupported colour conversion")
        } catch let error as HashError {
            guard case .frameExtractionFailed(let reason) = error else { throw error }
            #expect(reason.contains("Unsupported input (Operation not supported)"))
        }
        let trace = commands.withLock { $0 }
        #expect(trace.count == 2, "Only the duration probe and first extraction group should launch")
        let arguments = try #require(trace.last)
        let output = try #require(arguments.last)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: output).deletingLastPathComponent().path))
    }
}
