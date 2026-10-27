import Foundation
import Testing
@testable import VideoHash

/// Checks the sprite -> hash pipeline against values produced by the Go reference
/// (stash videophash / goimagehash v1.0.3 / nfnt/resize) on the same synthetic images.
@Suite("PHash Reference Parity Tests")
struct PHashReferenceParityTests {
    /// Deterministic pattern, mirrored in the Go program used to produce the expected hashes.
    private static func pattern(width: Int, height: Int, seed: Int) -> RGBImage {
        var image = RGBImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 3
                image.pixels[index + 0] = UInt8((x * 7 + y * 3 + seed * 11) % 256)
                image.pixels[index + 1] = UInt8((x * x / 97 + y * 5 + seed) % 256)
                image.pixels[index + 2] = UInt8(((x / 13) * (y / 9) + seed * 29) % 256)
            }
        }
        return image
    }

    private static func hash(_ sprite: RGBImage) throws -> String {
        let configuration = HashConfiguration.default
        let pixels = try ImageProcessor(configuration: configuration).processImage(sprite)
        let coefficients = try DCTProcessor(configuration: configuration).applyDCT(to: pixels)
        return try HashComputer(configuration: configuration).computeHash(from: coefficients)
    }

    @Test(
        "Sprite hash matches goimagehash PerceptionHash",
        arguments: [
            (800, 450, 1, "80012f3f3f3c7879"),
            (800, 1420, 2, "80126e00ff07b77f"),
            (800, 640, 3, "d0e480a783df0f1f"),
            (64, 64, 4, "b3250fda2c59d529"),  // No resize needed
            (37, 23, 5, "c812b61db535b617"),  // Upscale
        ]
    )
    func testMatchesReference(width: Int, height: Int, seed: Int, expected: String) throws {
        let hash = try Self.hash(Self.pattern(width: width, height: height, seed: seed))
        #expect(hash == expected)
    }

    @Test("Sprite composer tiles frames left to right, top to bottom")
    func testSpriteLayout() throws {
        let configuration = HashConfiguration(frameCount: 4, spriteColumns: 2, spriteRows: 2)
        let frames = (0..<4).map { index in
            RGBImage(width: 2, height: 1, pixels: [UInt8](repeating: UInt8(index * 10 + 10), count: 6))
        }

        let sprite = try SpriteComposer(configuration: configuration).composeSprite(from: frames)

        #expect(sprite.width == 4)
        #expect(sprite.height == 2)
        let reds = stride(from: 0, to: sprite.pixels.count, by: 3).map { sprite.pixels[$0] }
        #expect(reds == [10, 10, 20, 20, 30, 30, 40, 40])
    }

    @Test("Sprite composer rejects missing frames")
    func testSpriteInsufficientFrames() {
        let composer = SpriteComposer(configuration: .default)
        #expect(throws: HashError.self) {
            try composer.composeSprite(from: [RGBImage(width: 1, height: 1)])
        }
    }

    @Test("BMP decoder handles bottom-up rows, BGR order and row padding")
    func testBMPDecoding() throws {
        // 2x2, 24 bpp, rows padded from 6 to 8 bytes, bottom row first.
        var bmp: [UInt8] = [0x42, 0x4D]
        func append32(_ value: Int32) {
            withUnsafeBytes(of: value.littleEndian) { bmp.append(contentsOf: $0) }
        }
        func append16(_ value: Int16) {
            withUnsafeBytes(of: value.littleEndian) { bmp.append(contentsOf: $0) }
        }
        append32(54 + 16); append32(0); append32(54)
        append32(40); append32(2); append32(2); append16(1); append16(24)
        append32(0); append32(16); append32(0); append32(0); append32(0); append32(0)
        bmp += [3, 2, 1, 6, 5, 4, 0, 0]          // bottom row: (1,2,3) (4,5,6)
        bmp += [9, 8, 7, 12, 11, 10, 0, 0]       // top row: (7,8,9) (10,11,12)

        let image = try BMPDecoder.decode(Data(bmp))

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.pixels == [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6])
    }

    @Test("BMP decoder rejects malformed input")
    func testBMPMalformed() {
        #expect(throws: HashError.self) { try BMPDecoder.decode(Data([0x42, 0x4D, 0, 0])) }
        #expect(throws: HashError.self) { try BMPDecoder.decode(Data(repeating: 0, count: 64)) }
    }

    @Test("Duration is parsed from ffmpeg output with centisecond precision")
    func testDurationParsing() {
        let output = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'Video2.mp4':
          Duration: 00:00:21.43, start: 0.000000, bitrate: 258 kb/s
        """
        #expect(FrameExtractor.parseDuration(fromFFmpegOutput: output) == 21.43)
        #expect(FrameExtractor.parseDuration(fromFFmpegOutput: "  Duration: 01:02:05.07, start") == 3725.07)
        #expect(FrameExtractor.parseDuration(fromFFmpegOutput: "  Duration: N/A, bitrate: N/A") == nil)
    }
}
