import Foundation
import Testing
@testable import VideoHash

struct FFmpegDiagnosticsTests {
    private func read(_ bytes: Data) throws -> (excerpt: String, reportedDuration: Double?) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try FFmpegDiagnostics.read(from: url)
    }

    @Test func testBoundedExcerptAndDurationOutsideExcerpt() throws {
        var data = Data(repeating: 65, count: 200_000)
        data.append(Data("Duration: 01:02:05.07".utf8))
        data.append(Data(repeating: 66, count: 1_000_000))
        let result = try read(data)
        #expect(result.reportedDuration == 3725.07)
        #expect(result.excerpt.utf8.count <= 131_200)
        #expect(result.excerpt.contains("truncated"))
    }

    @Test func testDurationAcrossEveryChunkBoundary() throws {
        let text = "Duration: 00:00:21.43"
        for split in 1..<text.utf8.count {
            var data = Data(repeating: 65, count: 65536 - split)
            data.append(Data(text.utf8))
            #expect(try read(data).reportedDuration == 21.43)
        }
    }

    @Test func testMissingMalformedAndFirstDuration() throws {
        #expect(try read(Data("Duration: N/A".utf8)).reportedDuration == nil)
        #expect(try read(Data("Duration: 00:00:00.00 Duration: 01:00:00.00".utf8)).reportedDuration == 0)
        #expect(try read(Data("Duration: 999999999999999999999999:00:00.00 Duration: 01:00:00.00".utf8)).reportedDuration == nil)
        let unicode = "Duration: ٠٠:٠٠:٢١.٤٣ Duration: 00:00:22.00"
        #expect(try read(Data(unicode.utf8)).reportedDuration == FrameExtractor.parseDuration(fromFFmpegOutput: unicode))
        var data = Data([0xFF, 0xFE])
        data.append(Data("Duration: 00:00:21.43".utf8))
        // Invalid UTF-8 previously invalidated the whole diagnostic string.
        #expect(try read(data).reportedDuration == nil)
    }

    @Test func testNoisyProcessDoesNotBlockOnStderr() async throws {
        let result = try await FFmpegProcessRunner().run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "dd if=/dev/zero bs=65536 count=20 >&2 2>/dev/null"])
        #expect(result.status == 0)
        #expect(result.stderr.utf8.count <= 131_200)
    }
}
