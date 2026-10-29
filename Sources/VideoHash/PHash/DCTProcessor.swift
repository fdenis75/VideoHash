//
//  DCTProcessor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Applies Discrete Cosine Transform to image data
///
/// Ports goimagehash's `transforms.DCT2D`: an unscaled DCT-II computed with
/// Byeong Gi Lee's fast algorithm, applied to rows then columns.
struct DCTProcessor: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Apply 2D DCT to grayscale pixel data
    /// - Parameter pixels: 1D array of grayscale pixels (row-major order)
    /// - Returns: DCT coefficients (row-major order)
    /// - Throws: HashError if DCT computation fails
    func applyDCT(to pixels: [Double]) throws -> [Double] {
        let size = configuration.dctSize

        logger.debug("Applying 2D DCT to \(size)x\(size) data")

        guard pixels.count == size * size else {
            throw HashError.processingFailed(
                reason: "Invalid pixel count for DCT: expected \(size * size), got \(pixels.count)"
            )
        }
        guard size.nonzeroBitCount == 1 else {
            throw HashError.processingFailed(reason: "DCT size must be a power of 2, got \(size)")
        }

        return Self.dct2D(pixels, size: size)
    }

    static func dct2D(_ pixels: [Double], size: Int) -> [Double] {
        var data = pixels
        var line = [Double](repeating: 0.0, count: size)
        var temp = [Double](repeating: 0.0, count: size)

        // Rows
        for row in 0..<size {
            for col in 0..<size {
                line[col] = data[row * size + col]
            }
            dct1D(&line, temp: &temp)
            for col in 0..<size {
                data[row * size + col] = line[col]
            }
        }

        // Columns
        for col in 0..<size {
            for row in 0..<size {
                line[row] = data[row * size + col]
            }
            dct1D(&line, temp: &temp)
            for row in 0..<size {
                data[row * size + col] = line[row]
            }
        }

        return data
    }

    /// In-place unscaled DCT-II of a power-of-two length vector
    static func dct1D(_ values: inout [Double], temp: inout [Double]) {
        let count = values.count
        values.withUnsafeMutableBufferPointer { input in
            temp.withUnsafeMutableBufferPointer { scratch in
                guard let inputBase = input.baseAddress, let scratchBase = scratch.baseAddress else { return }
                forwardTransform(inputBase, scratchBase, count)
            }
        }
    }

    private static func forwardTransform(
        _ input: UnsafeMutablePointer<Double>,
        _ temp: UnsafeMutablePointer<Double>,
        _ length: Int
    ) {
        if length == 1 {
            return
        }

        let halfLength = length / 2
        for i in 0..<halfLength {
            let x = input[i]
            let y = input[length - 1 - i]
            temp[i] = x + y
            temp[i + halfLength] = (x - y) / (cos((Double(i) + 0.5) * Double.pi / Double(length)) * 2)
        }
        forwardTransform(temp, input, halfLength)
        forwardTransform(temp + halfLength, input, halfLength)
        for i in 0..<(halfLength - 1) {
            input[i * 2 + 0] = temp[i]
            input[i * 2 + 1] = temp[i + halfLength] + temp[i + halfLength + 1]
        }
        input[length - 2] = temp[halfLength - 1]
        input[length - 1] = temp[length - 1]
    }
}
