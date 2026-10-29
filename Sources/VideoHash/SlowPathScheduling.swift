//
//  SlowPathScheduling.swift
//  VideoHash
//

import Foundation

/// How a file that falls back to frame-by-frame extraction tells the batch
/// scheduler. The scheduler binds `onSlowPath` around each file's work;
/// `FrameExtractor` calls `began()` when it gives up on batch extraction.
/// A task-local, so the signal reaches the scheduler through the actors in
/// between without threading a callback through every call.
enum SlowExtraction {
    @TaskLocal static var onSlowPath: (@Sendable () -> Void)?

    static func began() { onSlowPath?() }
}

/// Runs a batch plan with at most `maxConcurrentTasks` files at once, plus
/// one extra slot per file that has fallen back to frame-by-frame extraction
/// (`SlowExtraction`), up to `maxExtraTasks` extra. A slow file can then take
/// minutes without holding back the rest; its extra slot goes away when it
/// finishes. Volumes are balanced as by `VolumeBalancedQueue`.
enum SlowPathAwareScheduler {
    private enum Event: Sendable {
        case slowPath(Int)
        case finished(Int, Result<HashResult, any Error>)
    }

    /// Calls `deliver` on the caller's task with each file's original index
    /// and outcome as it finishes; `deliver` returning false stops the batch
    /// (remaining files are cancelled). A file whose work throws
    /// `CancellationError` while the batch is cancelled is not delivered.
    static func run(
        plan: [HashBatchPlanner.Item],
        maxConcurrentTasks: Int,
        maxExtraTasks: Int,
        work: @escaping @Sendable (HashBatchPlanner.Item) async throws -> HashResult,
        deliver: (Int, Result<HashResult, any Error>) -> Bool
    ) async throws {
        guard !plan.isEmpty else { return }
        let (events, sink) = AsyncStream<Event>.makeStream()
        defer { sink.finish() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var queue = VolumeBalancedQueue(plan: plan)
            var running = 0
            var capacity = min(maxConcurrentTasks, plan.count)
            let maxCapacity = maxConcurrentTasks + max(0, maxExtraTasks)
            var boosted: Set<Int> = []
            var finished = 0

            func fill() {
                while running < capacity, let item = queue.next() {
                    running += 1
                    let index = item.originalIndex
                    group.addTask {
                        try Task.checkCancellation()
                        let result: Result<HashResult, any Error>
                        do {
                            let hash = try await SlowExtraction.$onSlowPath.withValue({ sink.yield(.slowPath(index)) }) {
                                try await work(item)
                            }
                            try Task.checkCancellation()
                            result = .success(hash)
                        } catch {
                            try Task.checkCancellation()
                            result = .failure(error)
                        }
                        sink.yield(.finished(index, result))
                    }
                }
            }

            fill()
            // Ends early (nil) when this task is cancelled.
            for await event in events {
                switch event {
                case .slowPath(let index):
                    guard capacity < maxCapacity, boosted.insert(index).inserted else { continue }
                    capacity += 1
                    fill()
                case .finished(let index, let result):
                    running -= 1
                    finished += 1
                    queue.finished(originalIndex: index)
                    if boosted.remove(index) != nil { capacity -= 1 }
                    try Task.checkCancellation()
                    guard deliver(index, result) else {
                        group.cancelAll()
                        return
                    }
                    if finished == plan.count { return }
                    fill()
                }
            }
            try Task.checkCancellation()
        }
    }
}
