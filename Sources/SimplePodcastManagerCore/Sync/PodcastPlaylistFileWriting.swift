import Foundation

public protocol PodcastPlaylistFileWriting: Sendable {
    func write(_ data: Data, to destinationURL: URL) throws
    func removeItemIfPresent(at targetURL: URL) throws
}

public struct LocalPodcastPlaylistFileWriter: PodcastPlaylistFileWriting {
    public init() {}

    public func write(_ data: Data, to destinationURL: URL) throws {
        try data.write(to: destinationURL, options: .atomic)
    }

    public func removeItemIfPresent(at targetURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        let sidecarURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("._\(targetURL.lastPathComponent)", isDirectory: false)
        if fileManager.fileExists(atPath: sidecarURL.path) {
            try fileManager.removeItem(at: sidecarURL)
        }
    }
}
