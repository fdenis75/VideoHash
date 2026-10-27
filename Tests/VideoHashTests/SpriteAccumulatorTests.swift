import Foundation
import Testing
@testable import VideoHash

struct SpriteAccumulatorTests {
    private let configuration = HashConfiguration(frameCount: 4, spriteColumns: 2, spriteRows: 2)

    @Test func testMixedFramesMatchOriginalComposition() throws {
        let frames = [
            RGBImage(width: 3, height: 2, pixels: [UInt8](repeating: 10, count: 18)),
            RGBImage(width: 5, height: 3, pixels: [UInt8](repeating: 20, count: 45)),
            RGBImage(width: 5, height: 3, pixels: [UInt8](repeating: 30, count: 45)),
            RGBImage(width: 1, height: 1, pixels: [60, 70, 80]),
        ]
        let expected = try SpriteComposer(configuration: configuration).composeSprite(from: frames)
        var accumulator = SpriteAccumulator(configuration: configuration)
        for frame in frames { accumulator.append(frame) }
        #expect(try accumulator.finish() == expected)
    }

    @Test func testMissingFramesFailWithActualCount() {
        var accumulator = SpriteAccumulator(configuration: configuration)
        accumulator.append(RGBImage(width: 1, height: 1))
        #expect(throws: HashError.insufficientFrames(expected: 4, actual: 1)) { try accumulator.finish() }
    }

    @Test func testAVFoundationPaddingAndErrorPrecedence() throws {
        let image = RGBImage(width: 1, height: 1, pixels: [1, 2, 3])
        var collection = FrameCollection(configuration: configuration, composeSprite: true)
        collection.append(image)
        collection.append(image)
        try collection.normalizeAVFoundation(successfulCount: 2, conversionError: nil)
        #expect(try collection.finishSprite() == SpriteComposer(configuration: configuration).composeSprite(from: [image, image, image, image]))
        var insufficient = FrameCollection(configuration: configuration, composeSprite: true)
        #expect(throws: HashError.insufficientFrames(expected: 4, actual: 1)) {
            try insufficient.normalizeAVFoundation(successfulCount: 1, conversionError: HashError.processingFailed(reason: "conversion"))
        }
        #expect(throws: HashError.processingFailed(reason: "conversion")) {
            try insufficient.normalizeAVFoundation(successfulCount: 2, conversionError: HashError.processingFailed(reason: "conversion"))
        }
    }

    @Test func testBMPTopDownRowsAndTruncation() throws {
        // 1x2 top-down, row padding from 3 to 4 bytes.
        var bmp = Data(repeating: 0, count: 62)
        bmp[0] = 0x42; bmp[1] = 0x4D; bmp[10] = 54
        bmp[14] = 40; bmp[18] = 1
        bmp[22] = 0xFE; bmp[23] = 0xFF; bmp[24] = 0xFF; bmp[25] = 0xFF
        bmp[26] = 1; bmp[28] = 24
        bmp.replaceSubrange(54..<62, with: [3, 2, 1, 0, 6, 5, 4, 0])
        #expect(try BMPDecoder.decode(bmp).pixels == [1, 2, 3, 4, 5, 6])
        #expect(throws: HashError.self) { try BMPDecoder.decode(bmp.prefix(61)) }
        #expect(throws: HashError.self) { try BMPDecoder.decode(bmp.prefix(20)) }
        bmp.replaceSubrange(18..<26, with: [255, 255, 255, 127, 255, 255, 255, 127])
        #expect(throws: HashError.self) { try BMPDecoder.decode(bmp) }
    }
}
