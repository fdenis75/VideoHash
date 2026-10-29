import Foundation

/// Incremental storage for the original left-to-right, top-to-bottom sprite layout.
struct SpriteAccumulator: Sendable {
    private let configuration: HashConfiguration
    private var sprite: RGBImage?
    private var cellWidth = 0
    private var cellHeight = 0
    private var count = 0

    init(configuration: HashConfiguration) {
        self.configuration = configuration
    }

    mutating func append(_ frame: RGBImage) {
        if sprite == nil {
            cellWidth = frame.width
            cellHeight = frame.height
            sprite = RGBImage(width: cellWidth * configuration.spriteColumns, height: cellHeight * configuration.spriteRows)
        }
        let index = count
        count += 1
        guard index < configuration.spriteColumns * configuration.spriteRows else { return }
        let originX = (index % configuration.spriteColumns) * cellWidth
        let originY = (index / configuration.spriteColumns) * cellHeight
        let copyWidth = min(frame.width, sprite!.width - originX)
        let copyHeight = min(frame.height, sprite!.height - originY)
        guard copyWidth > 0, copyHeight > 0 else { return }
        for y in 0..<copyHeight {
            let source = y * frame.width * 3
            let destination = ((originY + y) * sprite!.width + originX) * 3
            sprite!.pixels.replaceSubrange(
                destination..<(destination + copyWidth * 3),
                with: frame.pixels[source..<(source + copyWidth * 3)]
            )
        }
    }

    func finish() throws -> RGBImage {
        guard count >= configuration.frameCount else {
            throw HashError.insufficientFrames(expected: configuration.frameCount, actual: count)
        }
        guard let sprite else {
            throw HashError.processingFailed(reason: "No frames provided for sprite composition")
        }
        return sprite
    }
}
