//
//  RGBImage.swift
//  VideoHash
//

import Foundation
import CoreGraphics

/// Opaque 8-bit RGB image stored row-major, top-down (3 bytes per pixel).
///
/// The PHash pipeline works on raw pixels rather than `CGImage` so that sprite
/// composition, resizing and grayscale conversion are bit-exact with the Go
/// reference implementation (stash `videophash` + goimagehash).
struct RGBImage: Sendable, Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]
    
    /// Create a black image
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 3)
    }
    
    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3, "Pixel buffer size does not match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }
    
    /// Encode the exact packed RGB pixels as a top-down 24-bit BMP, without color conversion.
    func bmpData() -> Data {
        let stride = (width * 3 + 3) & ~3
        let imageSize = stride * height
        var data = Data([0x42, 0x4D])
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        append(UInt32(54 + imageSize))
        append(UInt32(0)) // Reserved
        append(UInt32(54)) // Pixel offset
        append(UInt32(40)) // BITMAPINFOHEADER size
        append(Int32(width))
        append(-Int32(height)) // Negative height stores rows top-down.
        append(UInt16(1)) // Planes
        append(UInt16(24)) // Bits per pixel
        append(UInt32(0)) // Uncompressed
        append(UInt32(imageSize))
        for _ in 0..<4 { append(UInt32(0)) } // Resolution and palette fields

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 3
                data.append(pixels[offset + 2])
                data.append(pixels[offset + 1])
                data.append(pixels[offset])
            }
            data.append(contentsOf: repeatElement(UInt8(0), count: stride - width * 3))
        }
        return data
    }

    /// Render a `CGImage` into an RGB buffer at its native size
    init(cgImage: CGImage, preserveSourceColorSpace: Bool = false) throws {
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            // FFmpeg's BMP path preserves video RGB values rather than applying an sRGB transfer.
            // Retain a tagged RGB source space when requested; use sRGB for untagged/non-RGB images.
            let sourceSpace = preserveSourceColorSpace && cgImage.colorSpace?.model == .rgb ? cgImage.colorSpace : nil
            guard let colorSpace = sourceSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else {
                return false
            }
            
            // Drawing directly preserves CGImage row order in the bitmap buffer.
            // A UIKit-style vertical transform would invert the pixels used for hashing.
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        
        guard drawn else {
            throw HashError.processingFailed(reason: "Failed to create RGB context for frame")
        }
        
        // 3. Pack 4-byte RGBA down to 3-byte RGB
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            pixels[i * 3 + 0] = rgba[i * 4 + 0]
            pixels[i * 3 + 1] = rgba[i * 4 + 1]
            pixels[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
