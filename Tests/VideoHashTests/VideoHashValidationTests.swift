import Foundation
import Testing
@testable import VideoHash

struct VideoHashValidationTests {
    @Test func testMissingFilePreservesError() async {
        let url = URL(fileURLWithPath: "/videohash-missing-\(UUID().uuidString)")
        let generator = VideoHashGenerator()
        await #expect(throws: HashError.fileNotFound(path: url.path)) { try await generator.generateHashes(for: url) }
        await #expect(throws: HashError.fileNotFound(path: url.path)) { try await generator.generatePHash(for: url) }
    }

    @Test func testNonVideoFailsValidation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let generator = VideoHashGenerator()
        for operation in [
            { _ = try await generator.generateHashes(for: url) },
            { _ = try await generator.generatePHash(for: url) }
        ] as [@Sendable () async throws -> Void] {
            let error = await #expect(throws: HashError.self) { try await operation() }
            guard case .invalidVideoFile = error else {
                Issue.record("Expected invalidVideoFile, got \(String(describing: error))")
                continue
            }
        }
    }
}
