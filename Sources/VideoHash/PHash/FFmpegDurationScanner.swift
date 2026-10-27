import Foundation

/// Recognizes the existing duration regex across arbitrary UTF-8 read boundaries.
/// Hours may have any number of digits; overflow invalidates the first match without
/// retaining an unbounded token or accidentally selecting a later duration.
struct FFmpegDurationScanner {
    private static let prefix = Array("Duration: ".utf8)
    private var position = 0
    private var hours = 0
    private var hasHours = false
    private var overflow = false
    private var fields = [0, 0, 0]
    private var matched = false
    private(set) var duration: Double?

    mutating func consume(_ scalar: Unicode.Scalar) {
        guard !matched else { return }
        if scalar.value < 128 {
            consume(UInt8(scalar.value), unsupportedDigit: false)
        } else if CharacterSet.decimalDigits.contains(scalar) {
            // The regex accepts Unicode digits, but Int(String) rejects them. Preserve
            // that first-match failure instead of selecting a later ASCII duration.
            consume(48, unsupportedDigit: true)
        } else {
            reset(0)
        }
    }

    private mutating func consume(_ byte: UInt8, unsupportedDigit: Bool) {
        guard !matched else { return }
        if position < Self.prefix.count {
            if byte == Self.prefix[position] { position += 1 }
            else { reset(byte) }
            return
        }
        let isDigit = byte >= 48 && byte <= 57
        if position == 10 {
            if isDigit {
                hasHours = true
                overflow = overflow || unsupportedDigit
                let product = hours.multipliedReportingOverflow(by: 10)
                let sum = product.partialValue.addingReportingOverflow(Int(byte - 48))
                overflow = overflow || product.overflow || sum.overflow
                hours = sum.partialValue
            } else if byte == 58 && hasHours { position += 1 }
            else { reset(byte) }
            return
        }
        if position == 13 || position == 16 {
            guard byte == (position == 13 ? 58 : 46) else { reset(byte); return }
        } else {
            guard isDigit else { reset(byte); return }
            overflow = overflow || unsupportedDigit
            let field = (position - 11) / 3
            fields[field] = fields[field] * 10 + Int(byte - 48)
        }
        position += 1
        if position == 19 {
            matched = true
            var total = hours
            for (multiplier, addition) in zip([60, 60, 100], fields) {
                let product = total.multipliedReportingOverflow(by: multiplier)
                let sum = product.partialValue.addingReportingOverflow(addition)
                overflow = overflow || product.overflow || sum.overflow
                total = sum.partialValue
            }
            if !overflow { duration = Double(total) / 100 }
        }
    }

    private mutating func reset(_ byte: UInt8) {
        if position == 0 {
            position = byte == Self.prefix[0] ? 1 : 0
            return
        }
        position = byte == Self.prefix[0] ? 1 : 0
        hours = 0
        hasHours = false
        overflow = false
        fields = [0, 0, 0]
    }
}
