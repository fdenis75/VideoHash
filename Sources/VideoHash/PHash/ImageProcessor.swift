//
//  ImageProcessor.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import CoreGraphics
import Logging

/// Processes sprite images for DCT analysis
actor ImageProcessor: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Convert sprite to grayscale and resize for DCT processing
    /// - Parameter sprite: Input sprite image
    /// - Returns: Grayscale pixel data (row-major order) sized for DCT
    /// - Throws: HashError if processing fails
    func processImage(_ sprite: CGImage) async throws -> [Float] {
        let dctSize = configuration.dctSize

        logger.debug("Processing image to \(dctSize)x\(dctSize) grayscale")

        // Create grayscale color space
        let colorSpace = CGColorSpaceCreateDeviceGray()

        // Create bitmap context for grayscale image
        guard let context = CGContext(
            data: nil,
            width: dctSize,
            height: dctSize,
            bitsPerComponent: 8,
            bytesPerRow: dctSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            logger.error("Failed to create grayscale context")
            throw HashError.processingFailed(reason: "Failed to create processing context")
        }

        // Bilinear interpolation is closer to videohashes/goimagehash behavior than Lanczos.
        context.interpolationQuality = .medium

        // Draw sprite into context (resized and converted to grayscale)
        let rect = CGRect(x: 0, y: 0, width: dctSize, height: dctSize)
        context.draw(sprite, in: rect)

        // Get grayscale image data
        guard let grayscaleImage = context.makeImage(),
              let dataProvider = grayscaleImage.dataProvider,
              let data = dataProvider.data as Data? else {
            logger.error("Failed to extract grayscale data")
            throw HashError.processingFailed(reason: "Failed to extract image data")
        }

        // Convert byte data to float array (normalized to 0.0-1.0)
        let pixelCount = dctSize * dctSize
        var pixels = [Float](repeating: 0.0, count: pixelCount)

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let bytePointer = bytes.bindMemory(to: UInt8.self)
            for i in 0..<pixelCount {
                // Normalize to 0.0-1.0 range
                pixels[i] = Float(bytePointer[i]) / 255.0
            }
        }

        logger.debug("Processed \(pixelCount) pixels to grayscale")

        return pixels
    }

    /// Extract 2D array from 1D pixel array for DCT
    /// - Parameter pixels: 1D array of grayscale pixels
    /// - Returns: 2D array (row-major order)
    /// - Throws: HashError if array size is invalid
    func extractMatrix(from pixels: [Float]) async throws -> [[Float]] {
        let size = configuration.dctSize
        let expectedCount = size * size

        guard pixels.count == expectedCount else {
            throw HashError.processingFailed(
                reason: "Invalid pixel count: expected \(expectedCount), got \(pixels.count)"
            )
        }

        var matrix = [[Float]](repeating: [Float](repeating: 0.0, count: size), count: size)

        for row in 0..<size {
            for col in 0..<size {
                let index = row * size + col
                matrix[row][col] = pixels[index]
            }
        }

        return matrix
    }
}
