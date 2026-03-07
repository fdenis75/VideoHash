import Foundation
import Testing
@testable import VideoHash

@Suite("Hash Batch Planner Tests")
struct HashBatchPlannerTests {
    @Test("Planner interleaves volumes while preserving in-volume order")
    func testInterleavesVolumes() {
        let urls = [
            URL(fileURLWithPath: "/Volumes/A/a1.mp4"),
            URL(fileURLWithPath: "/Volumes/A/a2.mp4"),
            URL(fileURLWithPath: "/Volumes/B/b1.mp4"),
            URL(fileURLWithPath: "/Volumes/C/c1.mp4"),
            URL(fileURLWithPath: "/Volumes/B/b2.mp4"),
            URL(fileURLWithPath: "/Volumes/A/a3.mp4")
        ]

        let plan = HashBatchPlanner.makePlan(for: urls) { url in
            let components = url.standardizedFileURL.pathComponents
            if components.count > 2 {
                return components[2]
            }
            return "/"
        }

        #expect(plan.map(\.originalIndex) == [0, 2, 3, 1, 4, 5])
        #expect(plan.map(\.volumeKey) == ["A", "B", "C", "A", "B", "A"])
    }

    @Test("Planner returns empty output for empty input")
    func testEmptyPlan() {
        let plan = HashBatchPlanner.makePlan(for: [])
        #expect(plan.isEmpty)
    }
}
