import Foundation
import Testing
@testable import VideoHash

/// Counts files in flight, to check the scheduler's limits.
private actor Gauge {
    private(set) var running = 0
    private(set) var peak = 0
    private var started: [Int] = []
    func start(_ index: Int) { running += 1; peak = max(peak, running); started.append(index) }
    func end() { running -= 1 }
    func startedOrder() -> [Int] { started }
}

@Suite("Slow Path Scheduling Tests")
struct SlowPathSchedulingTests {
    private func plan(_ count: Int) -> [HashBatchPlanner.Item] {
        let urls = (0..<count).map { URL(fileURLWithPath: "/Volumes/A/\($0).mp4") }
        return HashBatchPlanner.makePlan(for: urls) { _ in "A" }
    }

    private static let hash = HashResult(phash: "0", oshash: "0", duration: 1)

    @Test("A file on the slow path frees a slot for another file")
    func testSlowFileGetsExtraSlot() async throws {
        let gauge = Gauge()
        var delivered: [Int] = []
        // File 0 goes slow and waits until file 2 has started: with a single
        // slot, that only happens if the slow file lent a slot.
        let fileTwoStarted = AsyncStream<Void>.makeStream()
        try await SlowPathAwareScheduler.run(
            plan: plan(3), maxConcurrentTasks: 1, maxExtraTasks: 1,
            work: { item in
                await gauge.start(item.originalIndex)
                defer { Task { await gauge.end() } }
                if item.originalIndex == 2 { fileTwoStarted.continuation.yield() }
                if item.originalIndex == 0 {
                    SlowExtraction.began()
                    for await _ in fileTwoStarted.stream { break }
                }
                return Self.hash
            },
            deliver: { index, _ in delivered.append(index); return true }
        )
        #expect(Set(delivered) == [0, 1, 2])
        #expect(await gauge.peak == 2)
    }

    @Test("Extra slots are capped")
    func testExtraSlotsAreCapped() async throws {
        let gauge = Gauge()
        var delivered = 0
        try await SlowPathAwareScheduler.run(
            plan: plan(12), maxConcurrentTasks: 2, maxExtraTasks: 2,
            work: { item in
                await gauge.start(item.originalIndex)
                SlowExtraction.began()
                try await Task.sleep(for: .milliseconds(20))
                await gauge.end()
                return Self.hash
            },
            deliver: { _, _ in delivered += 1; return true }
        )
        #expect(delivered == 12)
        #expect(await gauge.peak <= 4)
        #expect(await gauge.peak > 2)
    }

    @Test("Without slow files the limit holds and order follows the plan")
    func testNoSlowFilesKeepsLimit() async throws {
        let gauge = Gauge()
        try await SlowPathAwareScheduler.run(
            plan: plan(8), maxConcurrentTasks: 1, maxExtraTasks: 4,
            work: { item in
                await gauge.start(item.originalIndex)
                await gauge.end()
                return Self.hash
            },
            deliver: { _, _ in true }
        )
        #expect(await gauge.peak == 1)
        #expect(await gauge.startedOrder() == Array(0..<8))
    }

    @Test("Stopping delivery ends the batch")
    func testDeliverFalseStops() async throws {
        var delivered = 0
        try await SlowPathAwareScheduler.run(
            plan: plan(10), maxConcurrentTasks: 1, maxExtraTasks: 0,
            work: { _ in Self.hash },
            deliver: { _, _ in delivered += 1; return false }
        )
        #expect(delivered == 1)
    }
}
