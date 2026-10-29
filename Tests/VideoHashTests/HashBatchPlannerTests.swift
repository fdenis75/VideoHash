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

    private func plan(_ volumes: [String]) -> [HashBatchPlanner.Item] {
        let urls = volumes.enumerated().map { URL(fileURLWithPath: "/Volumes/\($1)/\($0).mp4") }
        return HashBatchPlanner.makePlan(for: urls) { $0.standardizedFileURL.pathComponents[2] }
    }

    @Test("Balanced queue starts in plan order")
    func testQueueInitialOrderFollowsPlan() {
        let items = plan(["A", "A", "B", "C", "B", "A"])
        var queue = VolumeBalancedQueue(plan: items)
        let started = (0..<items.count).compactMap { _ in queue.next()?.originalIndex }
        #expect(started == items.map(\.originalIndex))
        #expect(queue.next() == nil)
    }

    @Test("A fast volume's freed slot goes back to it, not to the busy slow one")
    func testQueueRefillsLeastLoadedVolume() {
        var queue = VolumeBalancedQueue(plan: plan(["A", "A", "A", "A", "A", "B", "B", "B", "B", "B"]))
        var inFlight = (0..<4).compactMap { _ in queue.next() }
        #expect(inFlight.map(\.volumeKey) == ["A", "B", "A", "B"])
        // B's files keep finishing first; a fixed A,B,A,B order would now
        // have filled every slot with A.
        for _ in 0..<3 {
            let done = inFlight.firstIndex { $0.volumeKey == "B" }!
            queue.finished(originalIndex: inFlight.remove(at: done).originalIndex)
            inFlight.append(queue.next()!)
            #expect(inFlight.filter { $0.volumeKey == "B" }.count == 2)
        }
    }

    @Test("A volume with nothing left lends its slots to the others")
    func testQueueUsesAllSlotsWhenOneVolumeRunsOut() {
        var queue = VolumeBalancedQueue(plan: plan(["A", "B", "B", "B"]))
        let started = (0..<4).compactMap { _ in queue.next()?.volumeKey }
        #expect(started == ["A", "B", "B", "B"])
    }
}
