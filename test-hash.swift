#!/usr/bin/env swift

import Foundation
import VideoHash

@main
struct TestHash {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: test-hash.swift <video-path> [reference-tool-path]")
            return
        }

        let videoPath = CommandLine.arguments[1]
        let videoURL = URL(fileURLWithPath: videoPath)
        let referenceToolPath = CommandLine.arguments.count > 2
            ? CommandLine.arguments[2]
            : "/opt/bin/videohashes-amd64-macos"

        guard FileManager.default.fileExists(atPath: videoPath) else {
            print("Error: Video file not found: \(videoPath)")
            return
        }

        print("Testing VideoHash package...")
        print("Video: \(videoURL.lastPathComponent)")
        print("")

        let startTime = Date()

        let generator = VideoHashGenerator()
        let result = try await generator.generateHashes(for: videoURL)

        let elapsed = Date().timeIntervalSince(startTime)

        print("Results:")
        print("  PHash:    \(result.phash)")
        print("  OSHash:   \(result.oshash)")
        print("  Duration: \(Int(result.duration))s")
        print("  Time:     \(String(format: "%.2f", elapsed))s")

        if FileManager.default.isExecutableFile(atPath: referenceToolPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: referenceToolPath)
            process.arguments = [videoPath]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").map(String.init)
            let refPHash = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PHash:") }
                .map { $0.components(separatedBy: "PHash:").last?.trimmingCharacters(in: .whitespaces) ?? "" } ?? ""
            let refOSHash = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("OSHash:") }
                .map { $0.components(separatedBy: "OSHash:").last?.trimmingCharacters(in: .whitespaces) ?? "" } ?? ""

            print("")
            print("Reference (/opt/bin/videohashes-amd64-macos):")
            print("  PHash:    \(refPHash)")
            print("  OSHash:   \(refOSHash)")
            print("")
            print("Matches:")
            print("  PHash:    \(result.phash == refPHash)")
            print("  OSHash:   \(result.oshash == refOSHash)")
        } else {
            print("")
            print("Reference tool not found or not executable at: \(referenceToolPath)")
        }
    }
}
