//
//  SpriteComposer.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import CoreGraphics
import Logging

/// Composes extracted frames into a sprite grid image
actor SpriteComposer: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Compose frames into a sprite grid
    /// - Parameter frames: Array of extracted CGImages
    /// - Returns: CGImage containing all frames arranged in a grid
    /// - Throws: HashError if sprite creation fails
    func composeSprite(from frames: [CGImage]) async throws -> CGImage {
        guard frames.count >= configuration.frameCount else {
            throw HashError.insufficientFrames(
                expected: configuration.frameCount,
                actual: frames.count
            )
        }

        let rows = configuration.spriteRows
        let columns = configuration.spriteColumns

        guard let firstFrame = frames.first else {
            throw HashError.processingFailed(reason: "No frames provided for sprite composition")
        }

        // Match videohashes sprite behavior: preserve extracted frame dimensions.
        let cellWidth = firstFrame.width
        let cellHeight = firstFrame.height

        // Calculate sprite dimensions
        let spriteWidth = cellWidth * columns
        let spriteHeight = cellHeight * rows

        logger.debug("Creating \(spriteWidth)x\(spriteHeight) sprite with \(rows)x\(columns) grid")

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: spriteWidth,
            height: spriteHeight,
            bitsPerComponent: 8,
            bytesPerRow: spriteWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            logger.error("Failed to create CGContext")
            throw HashError.processingFailed(reason: "Failed to create sprite context")
        }

        // Fill with black background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: spriteWidth, height: spriteHeight))

        // Draw frames in grid (top to bottom, left to right)
        for frameIndex in 0..<min(frames.count, rows * columns) {
            let frame = frames[frameIndex]
            let x = (frameIndex % columns) * cellWidth
            let y = (frameIndex / columns) * cellHeight
            let destRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
            context.draw(frame, in: destRect)
        }

        // Create final sprite image
        guard let spriteImage = context.makeImage() else {
            logger.error("Failed to create sprite image")
            throw HashError.processingFailed(reason: "Failed to create sprite image")
        }

        logger.info("Created sprite: \(spriteImage.width)x\(spriteImage.height)")

        return spriteImage
    }
}
