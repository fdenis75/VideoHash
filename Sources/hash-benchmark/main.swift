import Foundation
import Synchronization
import VideoHash

@main
struct HashBenchmark {
    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard (5...6).contains(args.count), let limit = Int(args[3]), limit > 0,
              ["combined", "phash", "oshash", "batch", "stream", "client"].contains(args[2]) else {
            throw NSError(domain: "Usage: hash-benchmark <folder> <combined|phash|oshash|batch|stream|client> <concurrency> <output.json> [ffmpeg-inputs-per-process]", code: 1)
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: args[1]), includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension.lowercased() == "mp4" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { throw NSError(domain: "No MP4 fixtures", code: 2) }
        let inputLimit: Int?
        if args.count == 6 {
            guard let value = Int(args[5]), value > 0 else { throw NSError(domain: "Invalid FFmpeg input limit", code: 3) }
            inputLimit = value
        } else { inputLimit = nil }
        let launches = Mutex(0)
        let generator = try VideoHashGenerator(configuration: .default, ffmpegMaxInputsPerProcess: inputLimit) {
            launches.withLock { $0 += 1 }
        }
        let mode = args[2]
        let start = ContinuousClock.now
        var measurements: [Measurement] = []
        if mode == "batch" {
            let results = try await generator.generateHashes(for: urls, maxConcurrentTasks: limit)
            measurements = zip(urls, results).map { url, result in
                Measurement(file: url.lastPathComponent, seconds: nil, phash: result.phash, oshash: result.oshash, duration: result.duration)
            }
        } else if mode == "stream" {
            let stream = await generator.generateHashesStream(for: urls, maxConcurrentTasks: limit)
            for try await (_, url, result) in stream {
                let hashes = try result.get()
                measurements.append(
                    Measurement(file: url.lastPathComponent, seconds: nil, phash: hashes.phash, oshash: hashes.oshash, duration: hashes.duration)
                )
            }
            measurements.sort { $0.file < $1.file }
        } else if mode == "client" {
            measurements = try await withThrowingTaskGroup(of: Measurement.self) { group in
                var next = 0
                func enqueue() {
                    guard next < urls.count else { return }
                    let url = urls[next]
                    next += 1
                    group.addTask { try await measure(url, mode: "combined", generator: generator) }
                }
                for _ in 0..<min(limit, urls.count) { enqueue() }
                var values: [Measurement] = []
                while let value = try await group.next() {
                    values.append(value)
                    enqueue()
                }
                return values.sorted { $0.file < $1.file }
            }
        } else {
            for url in urls { measurements.append(try await measure(url, mode: mode, generator: generator)) }
        }
        let report = Report(mode: mode, concurrency: mode == "batch" || mode == "stream" || mode == "client" ? limit : 1,
                            seconds: seconds(since: start), measurements: measurements, ffmpegInputsPerProcess: inputLimit ?? VideoHashGenerator.defaultFFmpegInputsPerProcess, ffmpegLaunchAttempts: launches.withLock { $0 })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
    }

    static func measure(_ url: URL, mode: String, generator: VideoHashGenerator) async throws -> Measurement {
        let start = ContinuousClock.now
        if mode == "phash" {
            let hash = try await generator.generatePHash(for: url)
            return Measurement(file: url.lastPathComponent, seconds: seconds(since: start), phash: hash, oshash: nil, duration: nil)
        }
        if mode == "oshash" {
            let hash = try await generator.generateOSHash(for: url)
            return Measurement(file: url.lastPathComponent, seconds: seconds(since: start), phash: nil, oshash: hash, duration: nil)
        }
        let result = try await generator.generateHashes(for: url)
        return Measurement(file: url.lastPathComponent, seconds: seconds(since: start), phash: result.phash, oshash: result.oshash, duration: result.duration)
    }
}
