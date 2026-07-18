import Foundation

public protocol SyncStorageInspecting: Sendable {
    func availableCapacity(on device: DeviceInfo) throws -> Int64
    func fileSize(at url: URL) throws -> Int64
}

public struct LocalSyncStorageInspector: SyncStorageInspecting {
    public init() {}

    public func availableCapacity(on device: DeviceInfo) throws -> Int64 {
        let values = try device.rootURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let capacity = values.volumeAvailableCapacity else {
            throw SyncCapacityError.capacityUnavailable(device.rootURL)
        }
        return Int64(capacity)
    }

    public func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw SyncCapacityError.fileSizeUnavailable(url)
        }
        return Int64(size)
    }
}

public enum SyncCapacityError: LocalizedError, Equatable, Sendable {
    case capacityUnavailable(URL)
    case fileSizeUnavailable(URL)
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)
    case incompleteExistingCopy(fileName: String, expectedBytes: Int64, actualBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .capacityUnavailable(let url):
            return "Could not determine the available space on the device at \(url.path)."
        case .fileSizeUnavailable(let url):
            return "Could not determine the size of \(url.lastPathComponent)."
        case .insufficientCapacity(let requiredBytes, let availableBytes):
            return "The sync needs \(Self.formatted(requiredBytes)) of free space, but only \(Self.formatted(availableBytes)) is available even after the selected deletions."
        case .incompleteExistingCopy(let fileName, let expectedBytes, let actualBytes):
            return "\(fileName) on the device may be an incomplete copy (expected \(Self.formatted(expectedBytes)), found \(Self.formatted(actualBytes)). Select it for deletion and sync again."
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
