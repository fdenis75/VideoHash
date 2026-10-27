//
//  SpriteComposer.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Composes extracted frames into a sprite grid image
struct SpriteComposer: Sendable {
    private let configuration: HashConfiguration
    private let logger = Logger.phash

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    /// Compose frames into a sprite grid
    ///
    /// Mirrors stash's `combineImages`: cell size is taken from the first frame,
    /// frames are pasted left to right, top to bottom on a black canvas, and any
    /// frame larger than its cell is clipped by the canvas bounds only.
    /// - Parameter frames: Extracted frames
    /// - Returns: Sprite containing all frames arranged in a grid
    /// - Throws: HashError if sprite creation fails
    func composeSprite(from frames: [RGBImage]) throws -> RGBImage {
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

        let cellWidth = firstFrame.width
        let cellHeight = firstFrame.height
        var sprite = RGBImage(width: cellWidth * columns, height: cellHeight * rows)

        logger.debug("Creating \(sprite.width)x\(sprite.height) sprite with \(rows)x\(columns) grid")

        for frameIndex in 0..<min(frames.count, rows * columns) {
            let frame = frames[frameIndex]
            let originX = (frameIndex % columns) * cellWidth
            let originY = (frameIndex / columns) * cellHeight
            let copyWidth = min(frame.width, sprite.width - originX)
            let copyHeight = min(frame.height, sprite.height - originY)
            guard copyWidth > 0, copyHeight > 0 else { continue }

            for y in 0..<copyHeight {
                let source = y * frame.width * 3
                let destination = ((originY + y) * sprite.width + originX) * 3
                sprite.pixels.replaceSubrange(
                    destination..<(destination + copyWidth * 3),
                    with: frame.pixels[source..<(source + copyWidth * 3)]
                )
            }
        }

        logger.info("Created sprite: \(sprite.width)x\(sprite.height)")

        return sprite
    }
}
