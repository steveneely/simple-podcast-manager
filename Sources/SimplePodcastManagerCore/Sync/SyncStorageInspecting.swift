import Foundation

public protocol SyncStorageInspecting: Sendable {
    func availableCapacity(on device: DeviceInfo) throws -> Int64
    func fileSize(at url: URL) throws -> Int64
}

extension SyncStorageInspecting {
    func ensurePlanFits(_ actions: [SyncAction], on device: DeviceInfo) throws {
        var requiredCapacity: Int64 = 0
        var availableCapacity = try availableCapacity(on: device)

        for action in actions {
            switch action {
            case .copyToDevice(_, _, let fileSizeBytes):
                requiredCapacity = addingCapacity(
                    fileSizeBytes,
                    to: requiredCapacity
                )
            case .deleteFromDevice(_, let fileSizeBytes):
                availableCapacity = addingCapacity(
                    fileSizeBytes,
                    to: availableCapacity
                )
            case .skip, .ejectDevice:
                break
            }
        }

        guard requiredCapacity <= availableCapacity else {
            throw SyncCapacityError.insufficientCapacity(
                requiredBytes: requiredCapacity,
                availableBytes: availableCapacity
            )
        }
    }
}

private func addingCapacity(_ bytes: Int64, to total: Int64) -> Int64 {
    let (sum, overflowed) = total.addingReportingOverflow(bytes)
    return overflowed ? .max : sum
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
    case incompleteExistingCopy(targetURL: URL, expectedBytes: Int64, actualBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .capacityUnavailable(let url):
            return "Could not determine the available space on the device at \(url.path)."
        case .fileSizeUnavailable(let url):
            return "Could not determine the size of \(url.lastPathComponent)."
        case .insufficientCapacity(let requiredBytes, let availableBytes):
            return "There is not enough free space to copy all selected files. This sync plan requires \(Self.formatted(requiredBytes)), but only \(Self.formatted(availableBytes)) is available."
        case .incompleteExistingCopy(let targetURL, let expectedBytes, let actualBytes):
            return "\(targetURL.lastPathComponent) on the device may be an incomplete copy (expected \(Self.formatted(expectedBytes)), found \(Self.formatted(actualBytes))."
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
