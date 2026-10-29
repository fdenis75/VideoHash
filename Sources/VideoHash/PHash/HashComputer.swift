//
//  HashComputer.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Computes perceptual hash from DCT coefficients
struct HashComputer: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Compute PHash from DCT coefficients
    /// - Parameter dctCoefficients: DCT coefficients (row-major order)
    /// - Returns: Lowercase hexadecimal string representing the hash
    /// - Throws: HashError if hash computation fails
    func computeHash(from dctCoefficients: [Double]) throws -> String {
        let dctSize = configuration.dctSize
        let hashSize = configuration.hashSize

        logger.debug("Computing hash from DCT coefficients")

        guard dctCoefficients.count == dctSize * dctSize else {
            throw HashError.processingFailed(
                reason: "Invalid DCT coefficient count: expected \(dctSize * dctSize), got \(dctCoefficients.count)"
            )
        }

        // Extract low-frequency coefficients (top-left corner)
        var lowFreqCoeffs = [Double]()
        lowFreqCoeffs.reserveCapacity(hashSize * hashSize)

        for row in 0..<hashSize {
            for col in 0..<hashSize {
                let index = row * dctSize + col
                lowFreqCoeffs.append(dctCoefficients[index])
            }
        }

        guard lowFreqCoeffs.count == 64 else {
            throw HashError.processingFailed(
                reason: "Expected 64 hash bits, got \(lowFreqCoeffs.count)"
            )
        }

        logger.trace("First 8 coefficients: \(lowFreqCoeffs.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", "))")

        let median = Self.median(of: lowFreqCoeffs)
        logger.debug("Median of ALL coefficients (including DC): \(median)")

        // Strictly greater than median, packed MSB-first (matches goimagehash).
        var hashValue: UInt64 = 0
        for (index, coeff) in lowFreqCoeffs.enumerated() where coeff > median {
            hashValue |= (1 << UInt64(63 - index))
        }

        // Match videohashes output style: lowercase, non-padded hex.
        let hexString = String(hashValue, radix: 16)

        logger.debug("Computed hash: \(hexString)")

        return hexString
    }

    /// Port of goimagehash `etcs.MedianOfPixels`.
    ///
    /// Quickselect for the element at `count / 2`; for even counts it averages that
    /// element with the one left just before it after partitioning. Ported verbatim
    /// (including the `a/2 + b/2` averaging) so results are bit-identical to Go.
    static func median(of values: [Double]) -> Double {
        var sequence = values
        let count = sequence.count
        guard count > 0 else { return 0 }

        let k = count / 2
        var low = 0
        var high = count - 1

        if low == high {
            return sequence[k]
        }

        while low < high {
            let pivot = low / 2 + high / 2
            let pivotValue = sequence[pivot]
            var storeIndex = low
            sequence.swapAt(pivot, high)
            for i in low..<high where sequence[i] < pivotValue {
                sequence.swapAt(storeIndex, i)
                storeIndex += 1
            }
            sequence.swapAt(high, storeIndex)
            if k <= storeIndex {
                high = storeIndex
            } else {
                low = storeIndex + 1
            }
        }

        if count % 2 == 0 {
            return sequence[k - 1] / 2 + sequence[k] / 2
        }
        return sequence[k]
    }
}
