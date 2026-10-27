import Foundation
import Testing
@testable import VideoHash

@Suite("PHash HashComputer Tests")
struct PHashHashComputerTests {
    @Test("PHash uses > median and returns non-padded hex")
    func testMedianThresholdAndHexFormatting() throws {
        let config = HashConfiguration(
            frameCount: 25,
            frameWidth: 160,
            spriteColumns: 5,
            spriteRows: 5,
            dctSize: 8,
            hashSize: 8,
            useFFmpegFrameExtraction: false
        )
        let computer = HashComputer(configuration: config)

        // 31 lows, 2 middle values, 31 highs => median == 5 exactly.
        // As in goimagehash, values equal to the median map to 0 bits.
        let coefficients = ([Double](repeating: 0, count: 31)
            + [Double](repeating: 5, count: 2)
            + [Double](repeating: 10, count: 31))

        let hash = try computer.computeHash(from: coefficients)

        #expect(hash == "7fffffff")
    }

    @Test("Median matches goimagehash MedianOfPixels")
    func testMedian() {
        // Expected values produced by goimagehash v1.0.3 etcs.MedianOfPixels.
        #expect(HashComputer.median(of: [9, 1, 8, 2, 7, 3, 6, 4, 5, 0, 12, 11]) == 5.5)
        #expect(HashComputer.median(of: (0..<64).map { Double(($0 * 37) % 64) }) == 31.5)
        #expect(HashComputer.median(of: [3, 1, 2]) == 2)
    }

    @Test("Rejects wrong coefficient count")
    func testInvalidCoefficientCount() {
        let computer = HashComputer(configuration: .default)
        #expect(throws: HashError.self) {
            try computer.computeHash(from: [Double](repeating: 0, count: 10))
        }
    }
}
