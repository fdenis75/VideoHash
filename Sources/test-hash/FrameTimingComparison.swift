import Foundation

/// Matches this run's manifests by source path and sample index, never directory enumeration order.
enum FrameTimingComparison {
    static func printReport(in root: URL, runID: String) throws {
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var avFolders: [String: URL] = [:]
        var ffFolders: [String: URL] = [:]
        for folder in folders {
            guard (try? String(contentsOf: folder.appendingPathComponent("run.txt"), encoding: .utf8)) == runID else { continue }
            guard let source = try? String(contentsOf: folder.appendingPathComponent("source.txt"), encoding: .utf8) else { continue }
            if folder.lastPathComponent.hasSuffix("-avf") { avFolders[source] = folder }
            if folder.lastPathComponent.hasSuffix("-ffmpg") { ffFolders[source] = folder }
        }
        print("\nFrame timing comparison (FFmpeg minus AVFoundation; milliseconds):")
        print("FFmpeg times are relative to input start; edit lists/nonzero track starts may require timeline alignment.")
        for source in Set(avFolders.keys).union(ffFolders.keys).sorted() {
            print("  \(URL(fileURLWithPath: source).lastPathComponent)")
            guard let av = avFolders[source], let ff = ffFolders[source] else {
                print("    Missing backend diagnostics")
                continue
            }
            let avRows = try rows(at: av.appendingPathComponent("timestamps.csv"))
            let requests = try rows(at: ff.appendingPathComponent("requests.csv"))
            var avTimes: [Int: (requested: Double, actual: Double)] = [:]
            for row in avRows where row.count >= 9 {
                if let index = Int(row[0]), let requested = Double(row[4]), let actual = Double(row[7]) {
                    avTimes[index] = (requested, actual)
                }
            }
            var csv = ["sample_index,av_requested_seconds,ff_requested_seconds,av_actual_seconds,ff_actual_seconds,request_difference_ms,actual_difference_ms"]
            var distances: [Double] = []
            for row in requests where row.count >= 2 {
                guard let index = Int(row[0]), let requested = Double(row[1]) else { continue }
                let log = try? String(contentsOf: ff.appendingPathComponent("frame-\(index).bmp.timing.csv"), encoding: .utf8)
                guard let avTime = avTimes[index], let log, let actual = actualSeconds(from: log) else {
                    print("    Sample \(index): missing timestamp (not counted as a match)")
                    csv.append("\(index),,\(requested),,,,")
                    continue
                }
                let requestDelta = (requested - avTime.requested) * 1000
                let actualDelta = (actual - avTime.actual) * 1000
                distances.append(abs(actualDelta))
                print(String(format: "    %02d  AV %.6f  FF %.6f  Δactual %+.3f ms  Δrequest %+.3f ms", index, avTime.actual, actual, actualDelta, requestDelta))
                csv.append("\(index),\(avTime.requested),\(requested),\(avTime.actual),\(actual),\(requestDelta),\(actualDelta)")
            }
            if !distances.isEmpty {
                print(String(format: "    %d/%d samples; mean |Δ| %.3f ms; max |Δ| %.3f ms", distances.count, requests.count, distances.reduce(0, +) / Double(distances.count), distances.max()!))
            }
            try (csv.joined(separator: "\n") + "\n").write(to: ff.appendingPathComponent("comparison.csv"), atomically: true, encoding: .utf8)
        }
        print("Timing reports and BMPs: \(root.path)")
    }

    static func actualSeconds(from log: String) -> Double? {
        guard let line = log.split(separator: "\n").first else { return nil }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 5, fields[0] == "0", let pts = Double(fields[1]) else { return nil }
        let timeBase = fields[2].split(separator: "/")
        guard timeBase.count == 2, let numerator = Double(timeBase[0]),
              let denominator = Double(timeBase[1]), numerator > 0, denominator > 0,
              pts.isFinite, abs(pts) < Double(Int64.max) else { return nil }
        return pts * numerator / denominator
    }

    private static func rows(at url: URL) throws -> [[String]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").dropFirst().map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
    }
}
