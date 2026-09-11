import Foundation

public struct DevicePodcastConfiguration: Equatable, Sendable {
    public static let fileName = ".spmconfig"
    public static let sectionName = "simple-podcast-manager"
    public static let defaultPodcastDirectoryPath = "music"
    public static let defaultConfiguration = DevicePodcastConfiguration(
        uncheckedPodcastDirectoryPath: defaultPodcastDirectoryPath,
        uncheckedPlaylistDirectoryPath: nil
    )

    public var podcastDirectoryPath: String
    public var playlistDirectoryPath: String?

    public var resolvedPlaylistDirectoryPath: String {
        playlistDirectoryPath ?? podcastDirectoryPath
    }

    public init(
        podcastDirectoryPath: String = Self.defaultPodcastDirectoryPath,
        playlistDirectoryPath: String? = nil
    ) throws {
        self.podcastDirectoryPath = try Self.normalizedRelativeDirectoryPath(podcastDirectoryPath)
        self.playlistDirectoryPath = try playlistDirectoryPath.map(Self.normalizedPlaylistDirectoryPath)
    }

    private init(
        uncheckedPodcastDirectoryPath: String,
        uncheckedPlaylistDirectoryPath: String?
    ) {
        self.podcastDirectoryPath = uncheckedPodcastDirectoryPath
        self.playlistDirectoryPath = uncheckedPlaylistDirectoryPath
    }

    public init(contents: String) throws {
        var isInAppSection = false
        var podcastDirectoryPath: String?
        var playlistDirectoryPath: String?

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isInAppSection = section == Self.sectionName
                continue
            }

            guard isInAppSection else { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "podcast-dir" {
                podcastDirectoryPath = value
            } else if key == "playlist-dir" {
                playlistDirectoryPath = value
            }
        }

        try self.init(
            podcastDirectoryPath: podcastDirectoryPath ?? Self.defaultPodcastDirectoryPath,
            playlistDirectoryPath: playlistDirectoryPath
        )
    }

    public var contents: String {
        var lines = [
            "[\(Self.sectionName)]",
            "podcast-dir: \(podcastDirectoryPath)",
        ]
        if let playlistDirectoryPath {
            lines.append("playlist-dir: \(playlistDirectoryPath)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func normalizedRelativeDirectoryPath(_ path: String) throws -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultPodcastDirectoryPath
        }
        return try normalizedDirectoryPath(path) {
            DevicePodcastConfigurationError.invalidPodcastDirectoryPath(path)
        }
    }

    public static func normalizedPlaylistDirectoryPath(_ path: String) throws -> String {
        try normalizedDirectoryPath(path) {
            DevicePodcastConfigurationError.invalidPlaylistDirectoryPath(path)
        }
    }

    private static func normalizedDirectoryPath(
        _ path: String,
        error: () -> DevicePodcastConfigurationError
    ) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw error()
        }

        guard !trimmed.hasPrefix("~"), !trimmed.hasPrefix("/") else {
            throw error()
        }

        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw error()
        }

        return components.joined(separator: "/")
    }
}

public enum DevicePodcastConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case invalidPodcastDirectoryPath(String)
    case invalidPlaylistDirectoryPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPodcastDirectoryPath:
            return "Podcast folder must be a relative path inside the device."
        case .invalidPlaylistDirectoryPath:
            return "Playlist folder must be a relative path inside the device."
        }
    }
}
