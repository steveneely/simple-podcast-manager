import Foundation
import Testing
@testable import SimplePodcastManagerCore

@Suite(.timeLimit(.minutes(1)))
struct ProcessCommandRunnerTests {
    @Test
    func drainsBothPipesBeyondTheirBufferCapacity() async throws {
        let result = try await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "dd if=/dev/zero bs=1024 count=256 2>/dev/null; dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null"]
        )
        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput.utf8.count == 262_144)
        #expect(result.standardError.utf8.count == 262_144)
    }

    @Test
    func reportsExitStatusAndLaunchFailure() async throws {
        let result = try await ProcessCommandRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf failure >&2; exit 7"]
        )
        #expect(result.terminationStatus == 7)
        #expect(result.standardError == "failure")
        await #expect(throws: (any Error).self) {
            try await ProcessCommandRunner().run(
                executableURL: URL(fileURLWithPath: "/nonexistent/spm-command"), arguments: []
            )
        }
    }

    @Test
    func cancellationBeforeLaunchDoesNotRunTheCommand() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProcessCommandRunner().run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"]
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func cancellationStopsARunningCommand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = root.appendingPathComponent("ready")
        let task = Task {
            try await ProcessCommandRunner().run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $$ > \"$1.tmp\"; mv \"$1.tmp\" \"$1\"; exec /bin/sleep 3600", "spm-test", ready.path]
            )
        }
        defer { task.cancel() }
        // Synchronize on the child's readiness signal, not an assumed launch delay.
        while !FileManager.default.fileExists(atPath: ready.path) { await Task.yield() }
        let pid = try #require(Int32(String(contentsOf: ready, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(kill(pid, 0) == -1)
    }
}
