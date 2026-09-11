import Foundation

public struct M3UPlaylistEncoder: Sendable {
    public init() {}

    public func encode(
        fileURLs: [URL],
        relativeTo playlistDirectoryURL: URL,
        on device: DeviceInfo
    ) throws -> Data {
        let rootURL = device.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let resolvedPlaylistDirectoryURL = playlistDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedPlaylistDirectoryURL.path.hasPrefix(rootPath) else {
            throw SafetyValidationError.pathOutsideDeviceRoot(resolvedPlaylistDirectoryURL)
        }
        let playlistDirectoryComponents = relativePathComponents(
            for: resolvedPlaylistDirectoryURL,
            beneath: rootURL
        )
        var lines = ["#EXTM3U"]

        for fileURL in fileURLs {
            let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.path.hasPrefix(rootPath) else {
                throw SafetyValidationError.pathOutsideDeviceRoot(resolvedURL)
            }
            let fileComponents = relativePathComponents(for: resolvedURL, beneath: rootURL)
            let sharedComponentCount = zip(playlistDirectoryComponents, fileComponents)
                .prefix { pair in pair.0 == pair.1 }
                .count
            let relativeComponents = Array(
                repeating: "..",
                count: playlistDirectoryComponents.count - sharedComponentCount
            ) + Array(fileComponents.dropFirst(sharedComponentCount))
            let relativePath = relativeComponents.joined(separator: "\\")
            guard !relativePath.isEmpty,
                  !relativePath.contains("\n"),
                  !relativePath.contains("\r") else {
                throw PodcastPlaylistEncodingError.invalidEpisodePath(resolvedURL)
            }
            lines.append(relativePath)
        }

        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
            throw PodcastPlaylistEncodingError.couldNotEncodeUTF8
        }
        return data
    }

    private func relativePathComponents(for url: URL, beneath rootURL: URL) -> [String] {
        Array(url.pathComponents.dropFirst(rootURL.pathComponents.count))
    }
}

public enum PodcastPlaylistEncodingError: LocalizedError, Equatable, Sendable {
    case invalidEpisodePath(URL)
    case couldNotEncodeUTF8

    public var errorDescription: String? {
        switch self {
        case .invalidEpisodePath(let url):
            "Couldn’t add \(url.lastPathComponent) because its device path is invalid."
        case .couldNotEncodeUTF8:
            "Couldn’t encode the playlist as UTF-8."
        }
    }
}
