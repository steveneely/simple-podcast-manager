import Foundation

public enum SyncAction: Equatable, Sendable {
    case copyToDevice(sourceURL: URL, destinationURL: URL)
    case deleteFromDevice(targetURL: URL)
    case clearDeviceTrash(trashURL: URL)
    case ejectDevice(deviceRootURL: URL)
    case skip(reason: String)
}
