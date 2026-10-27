//
//  BMPDecoder.swift
//  VideoHash
//

import Foundation

/// Minimal decoder for the uncompressed 24-bit BMP files produced by ffmpeg's `bmp` encoder.
///
/// Decoding is done by hand (rather than through ImageIO) so no color management
/// is applied: pixel values must match what Go's `image/bmp` decoder returns.
enum BMPDecoder {
    static func decode(_ data: Data) throws -> RGBImage {
        return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in

            func readUInt16(_ offset: Int) -> Int {
                Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            }
            func readInt32(_ offset: Int) -> Int {
                Int(Int32(bitPattern: UInt32(bytes[offset])
                    | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 24))
            }

            guard bytes.count >= 54, bytes[0] == 0x42, bytes[1] == 0x4D else {
                throw HashError.frameExtractionFailed(reason: "Invalid BMP header")
            }

            let pixelOffset = readInt32(10)
            let width = readInt32(18)
            let rawHeight = readInt32(22)
            let bitsPerPixel = readUInt16(28)
            let compression = readInt32(30)

            guard bitsPerPixel == 24, compression == 0 else {
                throw HashError.frameExtractionFailed(
                    reason: "Unsupported BMP format: \(bitsPerPixel) bpp, compression \(compression)"
                )
            }

            // Positive height means rows are stored bottom-up.
            let bottomUp = rawHeight > 0
            let height = abs(rawHeight)
            guard width > 0, height > 0 else {
                throw HashError.frameExtractionFailed(reason: "Invalid BMP dimensions \(width)x\(rawHeight)")
            }

            let stride = (width * 3 + 3) & ~3
            let (pixelBytes, overflow) = stride.multipliedReportingOverflow(by: height)
            guard !overflow, pixelOffset >= 0, pixelOffset <= bytes.count, pixelBytes <= bytes.count - pixelOffset else {
                throw HashError.frameExtractionFailed(reason: "Truncated BMP pixel data")
            }

            var pixels = [UInt8](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                let sourceRow = pixelOffset + (bottomUp ? height - 1 - y : y) * stride
                let destinationRow = y * width * 3
                for x in 0..<width {
                    // BMP stores BGR
                    let source = sourceRow + x * 3
                    let destination = destinationRow + x * 3
                    pixels[destination + 0] = bytes[source + 2]
                    pixels[destination + 1] = bytes[source + 1]
                    pixels[destination + 2] = bytes[source + 0]
                }
            }

            return RGBImage(width: width, height: height, pixels: pixels)
        }
    }
}
