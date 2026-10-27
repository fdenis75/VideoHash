import Foundation

/// Owns each subprocess until exit, including when the requesting task is cancelled.
struct FFmpegProcessRunner: Sendable {
    var temporaryDirectory = FileManager.default.temporaryDirectory

    func run(executableURL: URL, arguments: [String]) async throws -> FFmpegProcessResult {
        let execution = ProcessExecution(executableURL: executableURL, arguments: arguments, temporaryDirectory: temporaryDirectory)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await withCheckedThrowingContinuation { continuation in
                execution.start(continuation)
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            execution.cancel()
        }
    }
}
