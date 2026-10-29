import Foundation

/// Race without a structured task group: a broken continuation must not keep the
/// test waiting for an uncooperative child. onTimeout releases external resources.
enum TestDeadline {
    static func value<T: Sendable>(
        of task: Task<T, any Error>,
        timeout: Duration = .seconds(5),
        onTimeout: @escaping @Sendable () -> Void
    ) async throws -> T {
        let stream = AsyncStream<Result<T, any Error>>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let observer = Task {
            stream.continuation.yield(await task.result)
            stream.continuation.finish()
        }
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
                onTimeout()
                stream.continuation.yield(.failure(NSError(domain: "VideoHash test deadline exceeded", code: 1)))
                stream.continuation.finish()
            } catch {}
        }
        defer {
            timer.cancel()
            observer.cancel()
            task.cancel()
            stream.continuation.finish()
        }
        for await result in stream.stream { return try result.get() }
        throw CancellationError()
    }
}
