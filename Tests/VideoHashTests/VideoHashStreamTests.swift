import Foundation
import Testing
@testable import VideoHash

struct VideoHashStreamTests {
    @Test func testEmptyStreamFinishes() async throws {
        let stream = await VideoHashGenerator().generateHashesStream(for: [], maxConcurrentTasks: 2)
        var count = 0
        for try await _ in stream { count += 1 }
        #expect(count == 0)
    }

    @Test(arguments: [0, -1])
    func testInvalidConcurrencyThrowsDuringIteration(limit: Int) async {
        let stream = await VideoHashGenerator().generateHashesStream(for: [], maxConcurrentTasks: limit)
        await #expect(throws: HashError.processingFailed(reason: "maxConcurrentTasks must be greater than zero")) {
            for try await _ in stream { Issue.record("Unexpected result") }
        }
    }

    @Test(arguments: [1, 2])
    func testFailedFilesDoNotStopQueue(limit: Int) async throws {
        let urls = (0..<5).map { _ in
            URL(fileURLWithPath: "/videohash-missing-\(UUID().uuidString)")
        }
        let stream = await VideoHashGenerator().generateHashesStream(for: urls, maxConcurrentTasks: limit)
        var received = Set<Int>()
        for try await (index, url, result) in stream {
            #expect(received.insert(index).inserted)
            #expect(url == urls[index])
            switch result {
            case .success:
                Issue.record("Missing file unexpectedly succeeded")
            case .failure(let error):
                #expect(error as? HashError == .fileNotFound(path: url.path))
            }
        }
        #expect(received == Set(urls.indices))
    }

    @Test func testAlreadyCancelledCallerThrows() async {
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { }
            return await VideoHashGenerator().generateHashesStream(for: [], maxConcurrentTasks: 1)
        }
        task.cancel()
        gate.continuation.finish()
        let stream = await task.value
        await #expect(throws: CancellationError.self) {
            for try await _ in stream { Issue.record("Unexpected result") }
        }
    }
}
