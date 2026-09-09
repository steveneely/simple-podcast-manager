import Foundation

public protocol CommandRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult
}

public struct CommandRunResult: Equatable, Sendable {
    public var terminationStatus: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        terminationStatus: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        let command = RunningCommand(executableURL: executableURL, arguments: arguments)
        return try await withTaskCancellationHandler {
            try command.start()
            // Drain both pipes concurrently while the child is alive. Waiting for exit
            // first can deadlock when either pipe fills.
            async let stdout = Task.detached {
                command.stdout.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let stderr = Task.detached {
                command.stderr.fileHandleForReading.readDataToEndOfFile()
            }.value
            await Task.detached { command.process.waitUntilExit() }.value
            let output = await (stdout, stderr)
            try Task.checkCancellation()
            return CommandRunResult(
                terminationStatus: command.process.terminationStatus,
                standardOutput: String(decoding: output.0, as: UTF8.self),
                standardError: String(decoding: output.1, as: UTF8.self)
            )
        } onCancel: {
            command.cancel()
        }
    }
}

/// The lock serializes launch and cancellation, including cancellation before launch.
private final class RunningCommand: @unchecked Sendable {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    private let lock = NSLock()
    private var cancelled = false

    init(executableURL: URL, arguments: [String]) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }
}
