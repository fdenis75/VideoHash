import Foundation

/// Retains bounded diagnostics while independently scanning the complete log for duration.
enum FFmpegDiagnostics {
    static let excerptLimit = 64 * 1024

    static func read(from url: URL) throws -> (excerpt: String, reportedDuration: Double?) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var head = Data()
        var tail = Data()
        var count = 0
        var scanner = FFmpegDurationScanner()
        var utf8 = UTF8Validator()
        while let chunk = try handle.read(upToCount: excerptLimit), !chunk.isEmpty {
            count += chunk.count
            if head.count < excerptLimit { head.append(chunk.prefix(excerptLimit - head.count)) }
            tail.append(chunk)
            if tail.count > excerptLimit { tail = Data(tail.suffix(excerptLimit)) }
            for byte in chunk {
                if let scalar = utf8.consume(byte) { scanner.consume(scalar) }
            }
        }
        let excerpt: String
        if count <= excerptLimit {
            excerpt = String(decoding: head, as: UTF8.self)
        } else if count <= excerptLimit * 2 {
            excerpt = String(decoding: head + tail.suffix(count - excerptLimit), as: UTF8.self)
        } else {
            excerpt = String(decoding: head, as: UTF8.self) + "\n[stderr truncated]\n" + String(decoding: tail, as: UTF8.self)
        }
        return (excerpt.trimmingCharacters(in: .whitespacesAndNewlines), utf8.isValid ? scanner.duration : nil)
    }

    /// Preserve the old all-or-nothing UTF-8 duration decoding without buffering the log.
    private struct UTF8Validator {
        private var valid = true
        private var remaining = 0
        private var scalarValue: UInt32 = 0
        private var lower: UInt8 = 0x80
        private var upper: UInt8 = 0xBF
        var isValid: Bool { valid && remaining == 0 }

        mutating func consume(_ byte: UInt8) -> Unicode.Scalar? {
            guard valid else { return nil }
            if remaining > 0 {
                valid = byte >= lower && byte <= upper
                scalarValue = (scalarValue << 6) | UInt32(byte & 0x3F)
                remaining -= 1
                lower = 0x80
                upper = 0xBF
            } else {
                switch byte {
                case 0...0x7F: return Unicode.Scalar(UInt32(byte))
                case 0xC2...0xDF: remaining = 1
                case 0xE0: remaining = 2; lower = 0xA0
                case 0xE1...0xEC, 0xEE...0xEF: remaining = 2
                case 0xED: remaining = 2; upper = 0x9F
                case 0xF0: remaining = 3; lower = 0x90
                case 0xF1...0xF3: remaining = 3
                case 0xF4: remaining = 3; upper = 0x8F
                default: valid = false
                }
                if remaining > 0 {
                    scalarValue = UInt32(byte & (remaining == 1 ? 0x1F : remaining == 2 ? 0x0F : 0x07))
                }
                return nil
            }
            return valid && remaining == 0 ? Unicode.Scalar(scalarValue) : nil
        }
    }
}
