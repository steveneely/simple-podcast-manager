import Foundation

public protocol DeviceService: Sendable {
    func discoverDevices() throws -> [DeviceInfo]
}
