import Foundation

public enum SyncAction: Equatable, Sendable {
    case copyToDevice(sourceURL: URL, destinationURL: URL)
    case deleteFromDevice(targetURL: URL)
    case ejectDevice(deviceRootURL: URL)
    case skip(reason: String)

    public var summaryDescription: String {
        switch self {
        case .copyToDevice(_, let destinationURL):
            return "Copy to device: \(podcastLabel(for: destinationURL)) / \(destinationURL.lastPathComponent)"
        case .deleteFromDevice(let targetURL):
            return "Delete old episode: \(podcastLabel(for: targetURL)) / \(targetURL.lastPathComponent)"
        case .ejectDevice:
            return "Eject device after sync"
        case .skip(let reason):
            return "Skip: \(reason)"
        }
    }

    private func podcastLabel(for fileURL: URL) -> String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }
}
