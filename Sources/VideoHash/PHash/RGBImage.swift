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

    /// Render a `CGImage` into an RGB buffer at its native size
    init(cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            throw HashError.processingFailed(reason: "Failed to create RGB context for frame")
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            pixels[i * 3 + 0] = rgba[i * 4 + 0]
            pixels[i * 3 + 1] = rgba[i * 4 + 1]
            pixels[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
