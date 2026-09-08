import Foundation

public struct M3UPlaylistEncoder: Sendable {
    public init() {}

    public func encode(fileURLs: [URL], on device: DeviceInfo) throws -> Data {
        let rootURL = device.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var lines = ["#EXTM3U"]

        for fileURL in fileURLs {
            let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.path.hasPrefix(rootPath) else {
                throw SafetyValidationError.pathOutsideDeviceRoot(resolvedURL)
            }
            let relativePath = String(resolvedURL.path.dropFirst(rootPath.count))
            guard !relativePath.isEmpty,
                  !relativePath.contains("\n"),
                  !relativePath.contains("\r") else {
                throw PodcastPlaylistEncodingError.invalidEpisodePath(resolvedURL)
            }
            lines.append("\\" + relativePath.replacingOccurrences(of: "/", with: "\\"))
        }

        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
            throw PodcastPlaylistEncodingError.couldNotEncodeUTF8
        }
        return data
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
