import Foundation
import VideoHash

@main
struct TestHash {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: test-hash <video-path-or-folder> [max-concurrent] [reference-tool-path]")
            return
        }

        let inputPath = CommandLine.arguments[1]
        let inputURL = URL(fileURLWithPath: inputPath)
        let maxConcurrentTasks = parseMaxConcurrentTasks(from: CommandLine.arguments) ?? 4
        let referenceToolPath = parseReferenceToolPath(from: CommandLine.arguments)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            print("Error: Path not found: \(inputPath)")
            return
        }

        if isDirectory(inputURL) {
            let fileURLs = try collectFiles(in: inputURL)
            guard !fileURLs.isEmpty else {
                print("No files found in folder: \(inputPath)")
                return
            }

            try await runFolderMode(
                fileURLs: fileURLs,
                folderURL: inputURL,
                maxConcurrentTasks: maxConcurrentTasks,
                referenceToolPath: referenceToolPath
            )
        } else {
            try await runSingleFileMode(
                videoURL: inputURL,
                maxConcurrentTasks: maxConcurrentTasks,
                referenceToolPath: referenceToolPath
            )
        }
    }

    private static func runSingleFileMode(
        videoURL: URL,
        maxConcurrentTasks: Int,
        referenceToolPath: String
    ) async throws {
        print("Testing VideoHash package...")
        print("Video: \(videoURL.lastPathComponent)")
        print("Concurrency: \(maxConcurrentTasks)")
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
            let reference = try runReferenceTool(
                at: referenceToolPath,
                for: videoURL
            )

            print("")
            print("Reference (\(referenceToolPath)):")
            print("  PHash:    \(reference.phash)")
            print("  OSHash:   \(reference.oshash)")
            print("  Time:     \(String(format: "%.2f", reference.elapsed))s")
            print("")
            print("Matches:")
            print("  PHash:    \(result.phash == reference.phash)")
            print("  OSHash:   \(result.oshash == reference.oshash)")
        } else {
            print("")
            print("Reference tool not found or not executable at: \(referenceToolPath)")
        }
    }

    private static func runFolderMode(
        fileURLs: [URL],
        folderURL: URL,
        maxConcurrentTasks: Int,
        referenceToolPath: String
    ) async throws {
        print("Testing VideoHash package...")
        print("Folder: \(folderURL.path)")
        print("Files: \(fileURLs.count)")
        print("Concurrency: \(maxConcurrentTasks)")
        print("")

        let generator = VideoHashGenerator()
        let startTime = Date()
        let results = try await generator.generateHashes(
            for: fileURLs,
            maxConcurrentTasks: maxConcurrentTasks
        )
        let elapsed = Date().timeIntervalSince(startTime)

        print("VideoHash results:")
        for (url, result) in zip(fileURLs, results) {
            print("  \(url.lastPathComponent)")
            print("    PHash:    \(result.phash)")
            print("    OSHash:   \(result.oshash)")
            print("    Duration: \(Int(result.duration))s")
        }
        print("  Total time: \(String(format: "%.2f", elapsed))s")

        guard FileManager.default.isExecutableFile(atPath: referenceToolPath) else {
            print("")
            print("Reference tool not found or not executable at: \(referenceToolPath)")
            return
        }

        let referenceStartTime = Date()
        let references = try await runReferenceToolBatch(
            at: referenceToolPath,
            for: fileURLs,
            maxConcurrentTasks: maxConcurrentTasks
        )
        let referenceElapsed = Date().timeIntervalSince(referenceStartTime)

        print("")
        print("Reference (\(referenceToolPath)):")
        for (url, reference) in zip(fileURLs, references) {
            print("  \(url.lastPathComponent)")
            print("    PHash:    \(reference.phash)")
            print("    OSHash:   \(reference.oshash)")
        }
        print("  Total time: \(String(format: "%.2f", referenceElapsed))s")

        let comparisons = zip(results, references).map { result, reference in
            (phash: result.phash == reference.phash, oshash: result.oshash == reference.oshash)
        }
        let matchingPHashCount = comparisons.filter(\.phash).count
        let matchingOSHashCount = comparisons.filter(\.oshash).count

        print("")
        print("Matches:")
        print("  PHash:    \(matchingPHashCount)/\(fileURLs.count)")
        print("  OSHash:   \(matchingOSHashCount)/\(fileURLs.count)")
    }

    private static func runReferenceToolBatch(
        at referenceToolPath: String,
        for fileURLs: [URL],
        maxConcurrentTasks: Int
    ) async throws -> [ReferenceResult] {
        return try await withThrowingTaskGroup(of: (Int, ReferenceResult).self) { group in
            var results = [ReferenceResult?](repeating: nil, count: fileURLs.count)
            var nextIndex = 0
            let limit = min(maxConcurrentTasks, fileURLs.count)

            func addNextTaskIfAvailable() {
                guard nextIndex < fileURLs.count else {
                    return
                }

                let currentIndex = nextIndex
                let url = fileURLs[currentIndex]
                nextIndex += 1

                group.addTask {
                    let result = try runReferenceTool(at: referenceToolPath, for: url)
                    return (currentIndex, result)
                }
            }

            for _ in 0..<limit {
                addNextTaskIfAvailable()
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                addNextTaskIfAvailable()
            }

            return try results.enumerated().map { index, result in
                guard let result else {
                    throw NSError(
                        domain: "TestHash",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing reference result at index \(index)"]
                    )
                }
                return result
            }
        }
    }

    private static func runReferenceTool(
        at referenceToolPath: String,
        for videoURL: URL
    ) throws -> ReferenceResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: referenceToolPath)
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
            elapsed: elapsed
        )
    }

    private static func collectFiles(in folderURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func parseMaxConcurrentTasks(from arguments: [String]) -> Int? {
        guard arguments.count > 2, let value = Int(arguments[2]), value > 0 else {
            return nil
        }
        return value
    }

    private static func parseReferenceToolPath(from arguments: [String]) -> String {
        if arguments.count > 3 {
            return arguments[3]
        }
        if arguments.count > 2, Int(arguments[2]) == nil {
            return arguments[2]
        }
        return "/opt/bin/videohashes-amd64-macos"
    }
}

private struct ReferenceResult {
    let phash: String
    let oshash: String
    let elapsed: TimeInterval
}
