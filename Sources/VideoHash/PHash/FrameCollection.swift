import Foundation

/// Production retains the sprite and final RGB frame only. Array collection is kept
/// for extraction parity tests and internal callers that need individual frames.
struct FrameCollection: Sendable {
    private let configuration: HashConfiguration
    private var sprite: SpriteAccumulator?
    private var lastFrame: RGBImage?
    private var count = 0
    private(set) var frames: [RGBImage] = []

    init(configuration: HashConfiguration, composeSprite: Bool) {
        self.configuration = configuration
        self.sprite = composeSprite ? SpriteAccumulator(configuration: configuration) : nil
    }

    mutating func append(_ image: RGBImage) {
        if sprite != nil { sprite!.append(image) }
        else { frames.append(image) }
        lastFrame = image
        count += 1
    }

    mutating func normalizeAVFoundation(successfulCount: Int, conversionError: (any Error)?) throws {
        guard successfulCount >= configuration.frameCount / 2, successfulCount > 0 else {
            throw HashError.insufficientFrames(expected: configuration.frameCount, actual: successfulCount)
        }
        // Previously CGImages were normalized before the first RGB conversion.
        // Insufficient-frame errors must therefore precede conversion errors.
        if let conversionError { throw conversionError }
        while count < configuration.frameCount {
            guard let lastFrame else {
                throw HashError.insufficientFrames(expected: configuration.frameCount, actual: count)
            }
            append(lastFrame)
        }
    }

    func finishSprite() throws -> RGBImage {
        guard let sprite else { throw HashError.processingFailed(reason: "No sprite requested") }
        return try sprite.finish()
    }
}
