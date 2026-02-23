import Foundation
import VideoHash
import Logging

@main
struct TestHash {
    static func main() async throws {
        // Enable debug logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .trace
            return handler
        }

        guard CommandLine.arguments.count > 1 else {
            print("Usage: test-hash <video-path>")
            return
        }

        let videoPath = CommandLine.arguments[1]
        let videoURL = URL(fileURLWithPath: videoPath)

        guard FileManager.default.fileExists(atPath: videoPath) else {
            print("Error: File not found: \(videoPath)")
            return
        }

        print("Testing VideoHash package (DEBUG MODE)...")
        print("Video: \(videoURL.lastPathComponent)")
        print("")

        let startTime = Date()

        let generator = VideoHashGenerator()
        let result = try await generator.generateHashes(for: videoURL)

        let elapsed = Date().timeIntervalSince(startTime)

        print("")
        print(String(repeating: "=", count: 60))
        print("FINAL RESULTS:")
        print(String(repeating: "=", count: 60))
        print("  PHash:    \(result.phash)")
        print("  OSHash:   \(result.oshash)")
        print("  Duration: \(Int(result.duration))s")
        print("  Time:     \(String(format: "%.2f", elapsed))s")
        print(String(repeating: "=", count: 60))
    }
}
