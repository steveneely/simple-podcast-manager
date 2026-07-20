import Foundation

public enum SyncAction: Equatable, Sendable {
    case copyToDevice(sourceURL: URL, destinationURL: URL, fileSizeBytes: Int64)
    case deleteFromDevice(targetURL: URL, fileSizeBytes: Int64)
    case ejectDevice(deviceRootURL: URL)
    case skip(reason: String)

    public var fileSizeBytes: Int64? {
        switch self {
        case .copyToDevice(_, _, let fileSizeBytes), .deleteFromDevice(_, let fileSizeBytes):
            return fileSizeBytes
        case .ejectDevice, .skip:
            return nil
        }
    }

    public var summaryDescription: String {
        switch self {
        case .copyToDevice(_, let destinationURL, _):
            return "Copy to device: \(podcastLabel(for: destinationURL)) / \(destinationURL.lastPathComponent)"
        case .deleteFromDevice(let targetURL, _):
            return "Delete old episode: \(podcastLabel(for: targetURL)) / \(targetURL.lastPathComponent)"
        case .ejectDevice:
            return "Eject device when finished"
        case .skip(let reason):
            return "Skip: \(reason)"
        }
    }

    private func podcastLabel(for fileURL: URL) -> String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }
}
