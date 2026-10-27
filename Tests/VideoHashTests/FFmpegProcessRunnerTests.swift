import Darwin
import Foundation
import Testing
@testable import VideoHash

@Suite(.serialized)
struct FFmpegProcessRunnerTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForFile(_ url: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: url.path) {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "Fixture never became ready", code: 1)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func testSuccessAndNonzeroExit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FFmpegProcessRunner(temporaryDirectory: root)
        let result = try await runner.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf diagnostic >&2; exit 7"])
        #expect(result.status == 7)
        #expect(result.stderr == "diagnostic")
        let success = try await runner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        #expect(success.status == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func testLaunchFailureCleansUp() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) {
            try await FFmpegProcessRunner(temporaryDirectory: root).run(executableURL: root.appendingPathComponent("missing"), arguments: [])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func testPreCancelledRequestDoesNotLaunch() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FFmpegProcessRunner(temporaryDirectory: root).run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func testCancellationWaitsForExitAndCleansUp(ignoreTermination: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = root.appendingPathComponent("ready")
        // A shell-only loop avoids grandchildren; the PID belongs to the process under test.
        let script = (ignoreTermination ? "trap '' TERM; " : "") + "echo $$ > \"$1\"; while :; do :; done"
        let task = Task {
            try await FFmpegProcessRunner(temporaryDirectory: root).run(
                executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, "fixture", ready.path])
        }
        defer { task.cancel() }
        try await waitForFile(ready)
        let pid = try #require(Int32(String(contentsOf: ready, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                kill(pid, SIGKILL)
            } catch {}
        }
        defer { watchdog.cancel() }
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: task) { kill(pid, SIGKILL) }
        }
        #expect(start.duration(to: .now) < .seconds(5))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["ready"])
    }

    @Test func testExitCancellationRaceAndIndependentSibling() async throws {
        let runner = FFmpegProcessRunner()
        for _ in 0..<30 {
            let task = Task { try await runner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: []) }
            await Task.yield()
            task.cancel()
            do { #expect(try await task.value.status == 0) }
            catch { #expect(error is CancellationError) }
        }
        async let sibling = runner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await sibling.status == 0)
    }
    @Test func testCancellingActiveRequestLeavesActiveSiblingRunning() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstReady = root.appendingPathComponent("first")
        let secondReady = root.appendingPathComponent("second")
        let runner = FFmpegProcessRunner(temporaryDirectory: root)
        let script = "echo $$ > \"$1\"; while :; do :; done"
        let first = Task { try await runner.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, "fixture", firstReady.path]) }
        let second = Task { try await runner.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, "fixture", secondReady.path]) }
        defer { first.cancel(); second.cancel() }
        try await waitForFile(firstReady)
        try await waitForFile(secondReady)
        let firstPID = try #require(Int32(String(contentsOf: firstReady, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let secondPID = try #require(Int32(String(contentsOf: secondReady, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                kill(firstPID, SIGKILL)
                kill(secondPID, SIGKILL)
            } catch {}
        }
        defer { watchdog.cancel() }
        first.cancel()
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: first) { kill(firstPID, SIGKILL) }
        }
        #expect(kill(firstPID, 0) == -1 && errno == ESRCH)
        #expect(kill(secondPID, 0) == 0)
        second.cancel()
        await #expect(throws: CancellationError.self) {
            try await TestDeadline.value(of: second) { kill(secondPID, SIGKILL) }
        }
        #expect(kill(secondPID, 0) == -1 && errno == ESRCH)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 2)
    }

}
