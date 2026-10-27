import AVFoundation
import Foundation
import Testing
@testable import VideoHash

struct FrameExtractionFallbackTests {
    @Test(arguments: [false, true])
    func testLateFailureRestartsAllFramesAndPreservesSlowSeek(malformedBMP: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("ffmpeg")
        let calls = root.appendingPathComponent("calls")
        let directory = root.appendingPathComponent("directory")
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        func bmp(_ value: UInt8) -> String {
            var bytes = Data(repeating: 0, count: 58)
            bytes[0] = 0x42; bytes[1] = 0x4D; bytes[2] = 58; bytes[10] = 54
            bytes[14] = 40; bytes[18] = 1; bytes[22] = 1; bytes[26] = 1; bytes[28] = 24
            bytes.replaceSubrange(54..<57, with: [value, value, value])
            return bytes.base64EncodedString()
        }
        let script = """
        #!/bin/sh
        if [ "$1" = '-hide_banner' ]; then echo 'Duration: 00:01:00.00' >&2; exit 1; fi
        batch=0; failed=0; input=0; mode=fast
        for arg; do
            [ "$arg" = '-map' ] && batch=1
            [ "$arg" = '-i' ] && input=1
            if [ "$arg" = '-ss' ] && [ "$input" = 1 ]; then mode=slow; fi
        done
        if [ "$batch" = 1 ]; then mode=batch; fi
        echo "$mode" >> \(quote(calls.path))
        if [ "$mode" = fast ]; then exit 1; fi
        for arg; do
            case "$arg" in
                *.bmp)
                    echo "$arg" > \(quote(directory.path))
                    if [ "$mode" = batch ]; then
                        echo '\(bmp(100))' | /usr/bin/base64 -D > "$arg"
                        if [ '\(malformedBMP)' = true ]; then
                            case "$arg" in *frame-5.bmp) echo malformed > "$arg";; esac
                        fi
                    else
                        echo '\(bmp(200))' | /usr/bin/base64 -D > "$arg"
                    fi
                    case "$arg" in *frame-5.bmp) failed=1;; esac
                    ;;
            esac
        done
        if [ "$mode" = batch ] && [ "$failed" = 1 ] && [ '\(malformedBMP)' = false ]; then exit 1; fi
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = HashConfiguration(ffmpegPath: executable.path)
        let extractor = FrameExtractor(configuration: configuration, extractionPolicy: try FFmpegExtractionPolicy(maxInputsPerProcess: 5))
        let url = root.appendingPathComponent("unused.mp4")
        let actual = try await extractor.extractSprite(from: AVURLAsset(url: url), url: url)
        #expect(actual.width == 5 && actual.height == 5)
        #expect(actual.pixels == [UInt8](repeating: 200, count: 75))
        let modes = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map(String.init)
        let batchCount = modes.prefix { $0 == "batch" }.count
        #expect(malformedBMP ? batchCount == 5 : (1...5).contains(batchCount))
        #expect(Array(modes.dropFirst(batchCount)) == ["fast"] + [String](repeating: "slow", count: 25))
        let lastOutput = try String(contentsOf: directory, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: lastOutput).deletingLastPathComponent().path))
    }
}
