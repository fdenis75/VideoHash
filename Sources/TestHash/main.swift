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
            print("Usage: test-hash <video-path> <all | ffmpeg | AvFoundation | classic>")
            return
        }
        
        let videoPath = CommandLine.arguments[1]
        let videoURL = URL(fileURLWithPath: videoPath)
        let mode = CommandLine.arguments[2]
        
        guard FileManager.default.fileExists(atPath: videoPath) else {
            print("Error: File not found: \(videoPath)")
            return
        }
        
        var runAv = false
        var runff = false
        var runNat = false
        
        switch  mode {
        case "all" :
            runAv = true
            runff = true
            runNat = true
        case "ffmpeg":
            runAv = false
            runff = true
            runNat = false
        case  "AvFoundation":
            runAv = true
            runff = false
            runNat = false
        default:
            runAv = false
            runff = true
            runNat = false
            
        }
        print("Testing VideoHash package (DEBUG MODE)...")
        print("Video: \(videoURL.lastPathComponent)")
        print("")
        
        
        
        let startTime = Date()
        if runff {
            let generator = VideoHashGenerator()
            let result = try await generator.generateHashes(for: videoURL)
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("")
            print(String(repeating: "=", count: 60))
            print("FINAL RESULTS: ffmpag")
            print(String(repeating: "=", count: 60))
            print("  PHash:    \(result.phash)")
            print("  OSHash:   \(result.oshash)")
            print("  Duration: \(Int(result.duration))s")
            print("  Time:     \(String(format: "%.2f", elapsed))s")
            print(String(repeating: "=", count: 60))
        }
        if runAv {
            let generator = VideoHashGenerator(configuration: .Avfoundation)
            let result = try await generator.generateHashes( for: videoURL)
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("")
            print(String(repeating: "=", count: 60))
            print("FINAL RESULTS: AVF")
            print(String(repeating: "=", count: 60))
            print("  PHash:    \(result.phash)")
            print("  OSHash:   \(result.oshash)")
            print("  Duration: \(Int(result.duration))s")
            print("  Time:     \(String(format: "%.2f", elapsed))s")
            print(String(repeating: "=", count: 60))
        }
        
        if runNat{
            let result = try runReferenceTool(for: videoURL)
            print("")
            print(String(repeating: "=", count: 60))
            print("FINAL RESULTS: AVF")
            print(String(repeating: "=", count: 60))
            print("  PHash:    \(result.phash)")
            print("  OSHash:   \(result.oshash)")
            print("  Duration: \(Int(result.duration))s")
            //  print("  Time:     \(String(format: "%.2f", elapsed))
            
        }
    }
    private struct ReferenceResult {
        let phash: String
        let oshash: String
        let duration: TimeInterval
    }
    
    private static func runReferenceTool(
        
        for videoURL: URL
    ) throws -> ReferenceResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Users/francois/Dev/VideoHash/Sources/test-hash/test-hash.swift")
        process.currentDirectoryURL = URL(fileURLWithPath: "/opt/bin/")
        process.arguments = [videoURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        
        let startTime = Date()
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let elapsed = Date().timeIntervalSince(startTime)
        let lines = output.split(separator: "\n").map(String.init)
        let phash = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PHash:") }
            .map { $0.components(separatedBy: "PHash:").last?.trimmingCharacters(in: .whitespaces) ?? "" } ?? ""
        let oshash = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("OSHash:") }
            .map { $0.components(separatedBy: "OSHash:").last?.trimmingCharacters(in: .whitespaces) ?? "" } ?? ""
        
        return ReferenceResult(
            phash: phash,
            oshash: oshash,
            duration: elapsed
        )
    }
}
   
