import Foundation
import Testing
@testable import VideoHash

@Suite("PHash HashComputer Tests")
struct PHashHashComputerTests {
    @Test("PHash uses >= median and returns non-padded hex")
    func testMedianThresholdAndHexFormatting() async throws {
        let config = HashConfiguration(
            frameCount: 25,
            frameWidth: 160,
            spriteColumns: 5,
            spriteRows: 5,
            dctSize: 8,
            hashSize: 8,
            useAccelerate: false,
            useFFmpegFrameExtraction: false
        )
        let computer = HashComputer(configuration: config)

        // 31 lows, 2 middle values, 31 highs => median == 5 exactly.
        // With >= median, the two middle values must map to 1 bits.
        let coefficients = ([Float](repeating: 0, count: 31)
            + [Float](repeating: 5, count: 2)
            + [Float](repeating: 10, count: 31))

        let hash = try await computer.computeHash(from: coefficients)

        #expect(hash == "1ffffffff")
    }
}
