//
//  ImageProcessor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Processes sprite images for DCT analysis
///
/// Ports goimagehash's PHash preprocessing: `resize.Resize(n, n, img, resize.Bilinear)`
/// from github.com/nfnt/resize followed by `transforms.Rgb2Gray`.
struct ImageProcessor: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Resize sprite and convert it to grayscale for DCT processing
    /// - Parameter sprite: Input sprite image
    /// - Returns: Grayscale luminance values in 0...255 (row-major order) sized for DCT
    /// - Throws: HashError if processing fails
    func processImage(_ sprite: RGBImage) throws -> [Double] {
        let dctSize = configuration.dctSize

        logger.debug("Processing image to \(dctSize)x\(dctSize) grayscale")

        guard sprite.width > 0, sprite.height > 0 else {
            throw HashError.processingFailed(reason: "Sprite has no pixels")
        }

        let resized = Self.resizeBilinear(sprite, width: dctSize, height: dctSize)

        var pixels = [Double](repeating: 0.0, count: dctSize * dctSize)
        for i in 0..<pixels.count {
            let r = Double(resized.pixels[i * 3 + 0])
            let g = Double(resized.pixels[i * 3 + 1])
            let b = Double(resized.pixels[i * 3 + 2])
            pixels[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        logger.debug("Processed \(pixels.count) pixels to grayscale")

        return pixels
    }

    // MARK: - nfnt/resize bilinear port

    /// Two-pass separable resize with 8-bit fixed point weights, matching nfnt/resize
    /// for `*image.NRGBA` input (the type stash's sprite canvas uses).
    static func resizeBilinear(_ image: RGBImage, width: Int, height: Int) -> RGBImage {
        if image.width == width && image.height == height {
            return image
        }

        let scaleX = Double(image.width) / Double(width)
        let scaleY = Double(image.height) / Double(height)

        // Horizontal pass, written transposed: temp is image.height wide and `width` tall.
        let horizontal = makeWeights(outputSize: width, scale: scaleX)
        var temp = RGBImage(width: image.height, height: width)
        filterRows(of: image, into: &temp, weights: horizontal)

        // Same pass again on the transposed image yields the untransposed result.
        let vertical = makeWeights(outputSize: height, scale: scaleY)
        var result = RGBImage(width: width, height: height)
        filterRows(of: temp, into: &result, weights: vertical)

        return result
    }

    private struct Weights {
        let coefficients: [Int16]
        let start: [Int]
        let filterLength: Int
    }

    /// Port of nfnt/resize `createWeights8` with the `linear` kernel (2 taps)
    private static func makeWeights(outputSize: Int, scale: Double) -> Weights {
        let blur = 1.0
        let filterLength = 2 * Int(max((blur * scale).rounded(.up), 1))
        let filterFactor = min(1.0 / (blur * scale), 1)

        var coefficients = [Int16](repeating: 0, count: outputSize * filterLength)
        var start = [Int](repeating: 0, count: outputSize)
        for y in 0..<outputSize {
            var interpX = scale * (Double(y) + 0.5) - 0.5
            start[y] = Int(interpX) - filterLength / 2 + 1
            interpX -= Double(start[y])
            for i in 0..<filterLength {
                let input = abs((interpX - Double(i)) * filterFactor)
                let kernel = input <= 1 ? 1 - input : 0
                coefficients[y * filterLength + i] = Int16(kernel * 256)
            }
        }

        return Weights(coefficients: coefficients, start: start, filterLength: filterLength)
    }

    /// Port of nfnt/resize `resizeNRGBA`/`resizeRGBA` for fully opaque pixels:
    /// filters each input row and writes it as a column of `output`.
    private static func filterRows(of input: RGBImage, into output: inout RGBImage, weights: Weights) {
        let maxX = input.width - 1

        for x in 0..<output.width {
            let row = x * input.width * 3
            for y in 0..<output.height {
                var r: Int32 = 0
                var g: Int32 = 0
                var b: Int32 = 0
                var sum: Int32 = 0
                let start = weights.start[y]
                let coefficientIndex = y * weights.filterLength

                for i in 0..<weights.filterLength {
                    let coefficient = Int32(weights.coefficients[coefficientIndex + i])
                    guard coefficient != 0 else { continue }

                    let xi = min(max(start + i, 0), maxX) * 3
                    r += coefficient * Int32(input.pixels[row + xi + 0])
                    g += coefficient * Int32(input.pixels[row + xi + 1])
                    b += coefficient * Int32(input.pixels[row + xi + 2])
                    sum += coefficient
                }

                let destination = (y * output.width + x) * 3
                output.pixels[destination + 0] = clampUInt8(r / sum)
                output.pixels[destination + 1] = clampUInt8(g / sum)
                output.pixels[destination + 2] = clampUInt8(b / sum)
            }
        }
    }

    private static func clampUInt8(_ value: Int32) -> UInt8 {
        UInt8(min(max(value, 0), 255))
    }
}
