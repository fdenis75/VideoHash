import CoreGraphics
import Foundation
import Testing
@testable import VideoHash

struct RGBImageColorTests {
    @Test("Preserving tagged video RGB avoids an extra transfer conversion and retains row order")
    func testPreserveSourceColorSpace() throws {
        let pixels: [UInt8] = [32, 64, 96, 128, 160, 192, 224, 96, 32, 64, 192, 128]
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.itur_709))
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: 6, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let preserved = try RGBImage(cgImage: image, preserveSourceColorSpace: true)
        let converted = try RGBImage(cgImage: image, preserveSourceColorSpace: false)
        #expect(preserved.pixels == pixels)
        #expect(converted.pixels != preserved.pixels)
        #expect(try BMPDecoder.decode(preserved.bmpData()) == preserved)
    }
}
