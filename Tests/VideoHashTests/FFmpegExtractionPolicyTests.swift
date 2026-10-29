import Testing
@testable import VideoHash

struct FFmpegExtractionPolicyTests {
    @Test func testUnboundedPolicyKeepsAllInputsInOneProcess() {
        #expect(FFmpegExtractionPolicy().groups(count: 25) == [0..<25])
        #expect(FFmpegExtractionPolicy().groups(count: 0).isEmpty)
    }

    @Test func testProductionPolicyBoundsInputsToTen() {
        #expect(FFmpegExtractionPolicy.production.groups(count: 25) == [0..<10, 10..<20, 20..<25])
        #expect(VideoHashGenerator.defaultFFmpegInputsPerProcess == 10)
    }

    @Test(arguments: [1, 5, 10, 25, Int.max])
    func testGroupsCoverEachSampleExactlyOnce(limit: Int) throws {
        let groups = try FFmpegExtractionPolicy(maxInputsPerProcess: limit).groups(count: 25)
        #expect(groups.flatMap { Array($0) } == Array(0..<25))
        #expect(groups.allSatisfy { $0.count <= limit })
        if limit == 10 { #expect(groups == [0..<10, 10..<20, 20..<25]) }
    }

    @Test(arguments: [0, -1])
    func testInvalidLimitRejected(limit: Int) {
        #expect(throws: HashError.self) { try FFmpegExtractionPolicy(maxInputsPerProcess: limit) }
    }
}
