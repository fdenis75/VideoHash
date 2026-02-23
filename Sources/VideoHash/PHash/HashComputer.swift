//
//  HashComputer.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Computes perceptual hash from DCT coefficients
actor HashComputer: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Compute PHash from DCT coefficients
    /// - Parameter dctCoefficients: DCT coefficients (row-major order)
    /// - Returns: Lowercase hexadecimal string representing the hash
    /// - Throws: HashError if hash computation fails
    func computeHash(from dctCoefficients: [Float]) async throws -> String {
        let dctSize = configuration.dctSize
        let hashSize = configuration.hashSize

        logger.debug("Computing hash from DCT coefficients")

        guard dctCoefficients.count == dctSize * dctSize else {
            throw HashError.processingFailed(
                reason: "Invalid DCT coefficient count: expected \(dctSize * dctSize), got \(dctCoefficients.count)"
            )
        }

        // Extract low-frequency coefficients (top-left corner)
        var lowFreqCoeffs = [Float]()
        lowFreqCoeffs.reserveCapacity(hashSize * hashSize)

        for row in 0..<hashSize {
            for col in 0..<hashSize {
                let index = row * dctSize + col
                lowFreqCoeffs.append(dctCoefficients[index])
            }
        }

        guard lowFreqCoeffs.count == hashSize * hashSize else {
            throw HashError.processingFailed(
                reason: "Failed to extract \(hashSize)x\(hashSize) coefficients"
            )
        }

        logger.debug("Extracted \(lowFreqCoeffs.count) low-frequency coefficients")
        logger.trace("First 8 coefficients: \(lowFreqCoeffs.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", "))")

        // Calculate median including DC component (matches goimagehash/imagehash behavior)
        let sortedCoeffs = lowFreqCoeffs.sorted()
        let median = calculateMedian(sortedCoeffs)

        logger.debug("Median of ALL coefficients (including DC): \(median)")
        logger.trace("Min coeff: \(String(format: "%.4f", sortedCoeffs.first ?? 0)), Max coeff: \(String(format: "%.4f", sortedCoeffs.last ?? 0))")

        // Generate binary hash (1 if >= median, 0 otherwise) to match goimagehash.
        var hashBits = [Bool]()
        hashBits.reserveCapacity(lowFreqCoeffs.count)

        for coeff in lowFreqCoeffs {
            hashBits.append(coeff >= median)
        }

        // Convert binary to UInt64
        guard hashBits.count == 64 else {
            throw HashError.processingFailed(
                reason: "Expected 64 hash bits, got \(hashBits.count)"
            )
        }

        var hashValue: UInt64 = 0
        for (index, bit) in hashBits.enumerated() {
            if bit {
                // Pack bits MSB-first (bit 0 goes to position 63)
                hashValue |= (1 << UInt64(63 - index))
            }
        }

        // Match videohashes output style: lowercase, non-padded hex.
        let hexString = String(hashValue, radix: 16)

        logger.debug("Computed hash: \(hexString)")

        return hexString
    }

    /// Calculate median of sorted array
    private func calculateMedian(_ sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0.0 }

        let count = sortedValues.count
        if count % 2 == 0 {
            // Even count: average of middle two values
            let mid1 = sortedValues[count / 2 - 1]
            let mid2 = sortedValues[count / 2]
            return (mid1 + mid2) / 2.0
        } else {
            // Odd count: middle value
            return sortedValues[count / 2]
        }
    }
}
