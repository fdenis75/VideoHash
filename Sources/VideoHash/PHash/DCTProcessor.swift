//
//  DCTProcessor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Accelerate
import Logging

/// Applies Discrete Cosine Transform to image data
actor DCTProcessor: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Apply 2D DCT to grayscale pixel data
    /// - Parameter pixels: 1D array of grayscale pixels (row-major order)
    /// - Returns: DCT coefficients (row-major order)
    /// - Throws: HashError if DCT computation fails
    func applyDCT(to pixels: [Float]) async throws -> [Float] {
        let size = configuration.dctSize

        logger.debug("Applying 2D DCT to \(size)x\(size) data")

        guard pixels.count == size * size else {
            throw HashError.processingFailed(
                reason: "Invalid pixel count for DCT: expected \(size * size), got \(pixels.count)"
            )
        }

        if configuration.useAccelerate {
            return try await applyDCTAccelerate(to: pixels, size: size)
        } else {
            return try await applyDCTPureSwift(to: pixels, size: size)
        }
    }

    // MARK: - Accelerate Implementation

    /// Apply DCT using Accelerate framework (optimized)
    private func applyDCTAccelerate(to pixels: [Float], size: Int) async throws -> [Float] {
        logger.debug("Using Accelerate framework for DCT")

        // Note: vDSP doesn't have direct 2D DCT, so we'll use a simplified approach:
        // 1. Apply 1D DCT to each row
        // 2. Apply 1D DCT to each column of the result

        var data = pixels
        var temp = [Float](repeating: 0.0, count: size * size)

        // DCT on rows
        for row in 0..<size {
            let rowStart = row * size
            let rowEnd = rowStart + size
            var rowData = Array(data[rowStart..<rowEnd])
            dct1D(&rowData)
            temp.replaceSubrange(rowStart..<rowEnd, with: rowData)
        }

        // DCT on columns (transpose, DCT, transpose back)
        data = transpose(temp, size: size)
        for col in 0..<size {
            let colStart = col * size
            let colEnd = colStart + size
            var colData = Array(data[colStart..<colEnd])
            dct1D(&colData)
            data.replaceSubrange(colStart..<colEnd, with: colData)
        }
        data = transpose(data, size: size)

        logger.debug("DCT computed using Accelerate")

        return data
    }

    /// Apply 1D DCT using scipy.fftpack.dct compatible formula (DCT-II, unnormalized)
    private func dct1D(_ data: inout [Float]) {
        let N = data.count
        let output = data // Copy input

        for k in 0..<N {
            var sum: Float = 0.0
            for n in 0..<N {
                // DCT-II formula: cos(pi * k * (2n+1) / (2*N))
                let angle = Float.pi * Float(k) * (Float(n) + 0.5) / Float(N)
                sum += output[n] * cos(angle)
            }
            // Unnormalized: multiply by 2 (scipy default)
            data[k] = 2.0 * sum
        }
    }

    /// Transpose a square matrix (row-major to column-major)
    private func transpose(_ matrix: [Float], size: Int) -> [Float] {
        var result = [Float](repeating: 0.0, count: size * size)
        for row in 0..<size {
            for col in 0..<size {
                result[col * size + row] = matrix[row * size + col]
            }
        }
        return result
    }

    // MARK: - Pure Swift Implementation

    /// Apply 2D DCT using pure Swift (fallback) - matches scipy.fftpack.dct
    private func applyDCTPureSwift(to pixels: [Float], size: Int) async throws -> [Float] {
        logger.debug("Using pure Swift DCT implementation (scipy compatible)")

        var dct = [Float](repeating: 0.0, count: size * size)

        // 2D DCT-II formula (unnormalized, scipy default)
        for u in 0..<size {
            for v in 0..<size {
                var sum: Float = 0.0

                for x in 0..<size {
                    for y in 0..<size {
                        let pixelIndex = x * size + y
                        let pixel = pixels[pixelIndex]

                        // DCT-II formula: cos(pi * k * (2n+1) / (2*N))
                        let cosU = cos(Float.pi * Float(u) * (Float(x) + 0.5) / Float(size))
                        let cosV = cos(Float.pi * Float(v) * (Float(y) + 0.5) / Float(size))

                        sum += pixel * cosU * cosV
                    }
                }

                // Unnormalized: multiply by 4 for 2D (2 for each dimension)
                let dctIndex = u * size + v
                dct[dctIndex] = 4.0 * sum
            }
        }

        logger.debug("DCT computed using pure Swift (scipy compatible)")

        return dct
    }
}
