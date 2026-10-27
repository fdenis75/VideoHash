import Darwin
import Foundation

/// All mutable state and Process access are confined to `queue`. Callbacks only enqueue
/// work. This bridges Foundation's lifecycle API without blocking a Swift executor.
final class ProcessExecution: @unchecked Sendable {
    private let queue = DispatchQueue(label: "VideoHash.ProcessExecution")
    private let executableURL: URL
    private let arguments: [String]
    private let logURL: URL
    private var process: Process?
    private var logHandle: FileHandle?
    private var continuation: CheckedContinuation<FFmpegProcessResult, any Error>?
    private var cancelled = false

    init(executableURL: URL, arguments: [String], temporaryDirectory: URL) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.logURL = temporaryDirectory.appendingPathComponent("videohash-ffmpeg-stderr-\(UUID().uuidString).log")
    }

    func start(_ continuation: CheckedContinuation<FFmpegProcessResult, any Error>) {
        queue.async { [self] in
            self.continuation = continuation
            guard !self.cancelled else {
                self.complete(.failure(CancellationError()))
                return
            }
            do {
                guard FileManager.default.createFile(atPath: self.logURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let handle = try FileHandle(forWritingTo: self.logURL)
                self.logHandle = handle
                let process = Process()
                process.executableURL = self.executableURL
                process.arguments = self.arguments
                process.standardError = handle
                process.standardOutput = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                process.terminationHandler = { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { self.didExit() }
                }
                
                self.process = process
                // Single-quote each component so it can be pasted into a shell verbatim.
 /*               let commandLine = ([self.executableURL.path] + self.arguments)
                    .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                    .joined(separator: " ")
                print(commandLine)*/
                try process.run()
            } catch {
                self.complete(.failure(error))
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            self.cancelled = true
            guard let process = self.process, process.isRunning else { return }
            process.terminate()
            // The captured owner keeps lifecycle state alive through escalation; identity
            // and isRunning checks prevent signalling a finished/replaced execution.
            self.queue.asyncAfter(deadline: .now() + 1) {
                guard self.process === process, process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func didExit() {
        guard let process else { return }
        if cancelled {
            complete(.failure(CancellationError()))
        } else {
            let diagnostics = try? FFmpegDiagnostics.read(from: logURL)
            complete(.success(FFmpegProcessResult(
                status: process.terminationStatus,
                stderr: diagnostics?.excerpt ?? "",
                reportedDuration: diagnostics?.reportedDuration
            )))
        }
    }

    private func complete(_ result: Result<FFmpegProcessResult, any Error>) {
        process?.terminationHandler = nil
        process = nil
        try? logHandle?.close()
        logHandle = nil
        try? FileManager.default.removeItem(at: logURL)
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: result)
    }
}
