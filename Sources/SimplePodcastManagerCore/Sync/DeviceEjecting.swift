import Foundation

public protocol DeviceEjecting: Sendable {
    func eject(device: DeviceInfo) throws
}

public struct DiskUtilityDeviceEjector: DeviceEjecting {
    public init() {}

    public func eject(device: DeviceInfo) throws {
        let output = try runDiskUtility(arguments: ["eject", device.rootURL.path])
        guard output.status == 0 else {
            throw SyncExecutionError.ejectFailed(device.rootURL.path, output.combinedOutput)
        }

        try waitForUnmount(deviceRootURL: device.rootURL, diskIdentifier: diskIdentifier(from: output.combinedOutput))
    }

    private func waitForUnmount(deviceRootURL: URL, diskIdentifier: String?) throws {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if !FileManager.default.fileExists(atPath: deviceRootURL.path) {
                return
            }

            if let diskIdentifier, !isDiskMounted(diskIdentifier) {
                return
            }

            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        throw SyncExecutionError.ejectFailed(deviceRootURL.path, "The volume still appears to be mounted.")
    }

    private func isDiskMounted(_ diskIdentifier: String) -> Bool {
        guard let output = try? runDiskUtility(arguments: ["info", diskIdentifier]), output.status == 0 else {
            return true
        }

        return output.combinedOutput.contains("Mounted:") && !output.combinedOutput.contains("Mounted:               No")
    }

    private func diskIdentifier(from output: String) -> String? {
        let pattern = #"(?:disk|/dev/disk)[0-9]+s?[0-9]*"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
            let range = Range(match.range, in: output)
        else {
            return nil
        }

        return String(output[range]).replacingOccurrences(of: "/dev/", with: "")
    }

    private func runDiskUtility(arguments: [String]) throws -> DiskUtilityOutput {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return DiskUtilityOutput(status: process.terminationStatus, output: output, error: error)
    }
}

private struct DiskUtilityOutput {
    var status: Int32
    var output: String
    var error: String

    var combinedOutput: String {
        [output, error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
