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
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: CommandRunResult(
                        terminationStatus: process.terminationStatus,
                        standardOutput: String(decoding: stdoutData, as: UTF8.self),
                        standardError: String(decoding: stderrData, as: UTF8.self)
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
