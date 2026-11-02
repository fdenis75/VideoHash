import Foundation
import AVFoundation
import CoreGraphics
@testable import VideoHash

struct ResultRow: Codable, Sendable {
    let source: String
    let variant: String
    let hash: String
    let referenceHash: String
    let distance: Int
    let mae: Double
    let bias: Double
    let timestampMismatches: Int
    let colorSpace: String
    let directory: String
}

func hash(_ frames: [RGBImage]) throws -> String {
    let config = HashConfiguration.default
    let sprite = try SpriteComposer(configuration: config).composeSprite(from: frames)
    let gray = try ImageProcessor(configuration: config).processImage(sprite)
    let dct = try DCTProcessor(configuration: config).applyDCT(to: gray)
    return try HashComputer(configuration: config).computeHash(from: dct)
}

func render(_ image: CGImage, width: Int, height: Int, sourceColor: Bool, quality: CGInterpolationQuality) throws -> RGBImage {
    let space = sourceColor ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let ok = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.interpolationQuality = quality
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard ok else { throw CocoaError(.coderInvalidValue) }
    var pixels = [UInt8](); pixels.reserveCapacity(width * height * 3)
    for i in 0..<(width * height) { pixels += rgba[(i * 4)..<(i * 4 + 3)] }
    return RGBImage(width: width, height: height, pixels: pixels)
}

func experiment(_ folder: URL, modes: [String], stamp: String) async throws -> [ResultRow] {
    let source = try String(contentsOf: folder.appendingPathComponent("source.txt"), encoding: .utf8)
    let url = URL(fileURLWithPath: source)
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let assetDuration = try await asset.load(.duration).seconds
    let track = try await asset.loadTracks(withMediaType: .video).first!
    let frameDuration = try await track.load(.minFrameDuration)
    let trackStart = try await track.load(.timeRange).start
    let nativeMode = modes.allSatisfy { $0.hasPrefix("native") }
    let thumbnail = AVAssetImageGenerator(asset: asset)
    thumbnail.appliesPreferredTrackTransform = true
    thumbnail.requestedTimeToleranceBefore = .zero; thumbnail.requestedTimeToleranceAfter = .zero
    thumbnail.maximumSize = CGSize(width: 160, height: 10000)
    let full = AVAssetImageGenerator(asset: asset)
    full.appliesPreferredTrackTransform = true
    full.requestedTimeToleranceBefore = .zero; full.requestedTimeToleranceAfter = .zero
    var reference = [RGBImage]()
    var variants = Dictionary(uniqueKeysWithValues: modes.map { ($0, [RGBImage]()) })
    var mismatches = 0
    var colorSpace = ""
    var times = ["sample_index,requested,actual"]
    for i in 0..<25 {
        try Task.checkCancellation()
        let ref = try BMPDecoder.decode(Data(contentsOf: folder.appendingPathComponent("frame-\(i).bmp")))
        reference.append(ref)
        let stats = try String(contentsOf: folder.appendingPathComponent("frame-\(i).bmp.timing.csv"), encoding: .utf8).split(separator: "\n")[0].split(separator: ",")
        let tb = stats[2].split(separator: "/")
        let referenceTime = CMTime(value: Int64(stats[1])! * Int64(tb[0])!, timescale: Int32(tb[1])!)
        let requested: CMTime
        if nativeMode {
            let duration = (assetDuration * 100).rounded() / 100
            let sample = duration * 0.05 + Double(i) * (duration * 0.9 / 25)
            if modes.contains(where: { $0.contains("cursor") }) {
                let target = CMTime(seconds: sample, preferredTimescale: 1_000_000)
                let cursor = track.makeSampleCursor(presentationTimeStamp: target)!
                while CMTimeCompare(cursor.presentationTimeStamp, target) < 0 {
                    guard cursor.stepInPresentationOrder(byCount: 1) == 1 else { throw CocoaError(.coderInvalidValue) }
                }
                requested = cursor.presentationTimeStamp
            } else {
                let frameIndex = Int64(ceil((sample - trackStart.seconds) / frameDuration.seconds))
                requested = CMTimeAdd(trackStart, CMTime(value: frameIndex * frameDuration.value, timescale: frameDuration.timescale))
            }
        } else { requested = referenceTime }
        let (image, actual) = try await thumbnail.image(at: requested)
        if CMTimeCompare(referenceTime, actual) != 0 { mismatches += 1 }
        times.append("\(i),\(requested.seconds),\(actual.seconds)")
        colorSpace = image.colorSpace?.name as String? ?? "unnamed"
        for mode in modes where mode.hasPrefix("thumb") || mode.hasPrefix("native") {
            variants[mode]!.append(try render(image, width: ref.width, height: ref.height, sourceColor: mode.contains("source"), quality: .none))
        }
        if modes.contains(where: { $0.hasPrefix("full") }) {
            let (large, fullActual) = try await full.image(at: requested)
            if CMTimeCompare(requested, fullActual) != 0 { throw CocoaError(.coderInvalidValue) }
            for mode in modes where mode.hasPrefix("full") {
                let quality: CGInterpolationQuality = mode.contains("high") ? .high : mode.contains("medium") ? .medium : .low
                variants[mode]!.append(try render(large, width: ref.width, height: ref.height, sourceColor: mode.contains("source"), quality: quality))
            }
        }
    }
    let referenceHash = try hash(reference)
    var result = [ResultRow]()
    for mode in modes {
        let frames = variants[mode]!
        let directory = URL(fileURLWithPath: "/Users/francois/Dev/VideoHash/temp").appendingPathComponent("\(url.lastPathComponent)-\(stamp)-\(mode)-avf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: directory.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
        try times.joined(separator: "\n").write(to: directory.appendingPathComponent("timestamps.csv"), atomically: true, encoding: .utf8)
        var error = 0.0, bias = 0.0, count = 0
        for (i, frame) in frames.enumerated() {
            try frame.bmpData().write(to: directory.appendingPathComponent(String(format: "frame-%03d.bmp", i + 1)))
            for (a, b) in zip(frame.pixels, reference[i].pixels) {
                let d = Double(a) - Double(b); error += abs(d); bias += d; count += 1
            }
        }
        let h = try hash(frames)
        result.append(ResultRow(source: source, variant: mode, hash: h, referenceHash: referenceHash, distance: (UInt64(h, radix: 16)! ^ UInt64(referenceHash, radix: 16)!).nonzeroBitCount, mae: error / Double(count), bias: bias / Double(count), timestampMismatches: mismatches, colorSpace: colorSpace, directory: directory.path))
    }
    return result
}

@main struct Run {
    static func main() async throws {
        let args = CommandLine.arguments
        let runID = args[1]
        let modes = args[2].split(separator: ",").map(String.init)
        let output = URL(fileURLWithPath: args[3])
        let root = URL(fileURLWithPath: "/Users/francois/Dev/VideoHash/temp")
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter {
            $0.lastPathComponent.hasSuffix("-ffmpg") && (try? String(contentsOf: $0.appendingPathComponent("run.txt"), encoding: .utf8)) == runID
        }
        let stamp = "experiment-\(Int(Date().timeIntervalSince1970))"
        let results = try await withThrowingTaskGroup(of: [ResultRow].self) { group in
            for folder in folders { group.addTask { try await experiment(folder, modes: modes, stamp: stamp) } }
            var rows = [ResultRow]()
            for try await rowsForFile in group { rows += rowsForFile }
            return rows.sorted { ($0.source, $0.variant) < ($1.source, $1.variant) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: output)
        for r in results { print("\(URL(fileURLWithPath: r.source).lastPathComponent) | \(r.variant) | distance=\(r.distance) MAE=\(r.mae) bias=\(r.bias) timeMismatch=\(r.timestampMismatches) space=\(r.colorSpace)") }
    }
}
