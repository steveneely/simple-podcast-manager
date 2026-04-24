import Foundation

public protocol DeviceEjecting: Sendable {
    func eject(device: DeviceInfo) throws
}

public struct DiskUtilityDeviceEjector: DeviceEjecting {
    public init() {}

    public func eject(device: DeviceInfo) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", device.rootURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SyncExecutionError.ejectFailed(device.rootURL.path)
        }
    }
}
