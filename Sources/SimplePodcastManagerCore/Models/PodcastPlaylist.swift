import Foundation

public struct PodcastPlaylistEpisodeID: Codable, Equatable, Hashable, Sendable {
    public var subscriptionID: UUID
    public var episodeID: String

    public init?(episode: Episode) {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        self.subscriptionID = subscriptionID
        self.episodeID = episode.id
    }
}

public struct PodcastPlaylistEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: PodcastPlaylistEpisodeID
    public var episode: Episode

    public init?(episode: Episode) {
        guard let id = PodcastPlaylistEpisodeID(episode: episode) else { return nil }
        self.id = id
        self.episode = episode
    }
}

public struct PodcastPlaylist: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var deviceFileName: String
    public var entries: [PodcastPlaylistEntry]

    public init(
        id: UUID = UUID(),
        name: String,
        deviceFileName: String? = nil,
        entries: [PodcastPlaylistEntry] = []
    ) throws {
        let validatedName = try PodcastPlaylistName.validated(name)
        self.id = id
        self.name = validatedName
        self.deviceFileName = deviceFileName ?? PodcastPlaylistName.deviceFileName(for: validatedName)
        self.entries = entries
    }

    public func contains(_ episode: Episode) -> Bool {
        guard let id = PodcastPlaylistEpisodeID(episode: episode) else { return false }
        return entries.contains { $0.id == id }
    }
}

public struct PodcastPlaylistLibrary: Codable, Equatable, Sendable {
    public var playlists: [PodcastPlaylist]
    public var deviceStates: [String: PodcastPlaylistDeviceState]

    public init(
        playlists: [PodcastPlaylist] = [],
        deviceStates: [String: PodcastPlaylistDeviceState] = [:]
    ) {
        self.playlists = playlists
        self.deviceStates = deviceStates
    }
}

public struct PodcastPlaylistDeviceState: Codable, Equatable, Sendable {
    public var ownedDeviceFileNames: Set<String>
    public var pendingDeletedDeviceFileNames: Set<String>

    public init(
        ownedDeviceFileNames: Set<String> = [],
        pendingDeletedDeviceFileNames: Set<String> = []
    ) {
        self.ownedDeviceFileNames = ownedDeviceFileNames
        self.pendingDeletedDeviceFileNames = pendingDeletedDeviceFileNames
    }
}

public enum PodcastPlaylistName {
    private static let forbiddenCharacters = CharacterSet(charactersIn: "<>:\"/\\|?*")
    private static let reservedFATNames: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ]

    public static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PodcastPlaylistError.emptyName }
        guard !trimmed.hasPrefix("."),
              !trimmed.hasSuffix("."),
              !reservedFATNames.contains(trimmed.uppercased()),
              trimmed.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !forbiddenCharacters.contains(scalar)
        }) else {
            throw PodcastPlaylistError.invalidName
        }
        guard trimmed.utf8.count <= 180 else { throw PodcastPlaylistError.nameTooLong }
        return trimmed
    }

    public static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func deviceFileName(for name: String) -> String {
        "\(name).m3u"
    }
}

public enum PodcastPlaylistError: LocalizedError, Equatable, Sendable {
    case emptyName
    case invalidName
    case nameTooLong
    case duplicateName
    case missingEpisodeIdentity

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            "Playlist name can’t be empty."
        case .invalidName:
            "That playlist name can’t be used safely as a device filename."
        case .nameTooLong:
            "Playlist name must be 180 UTF-8 bytes or fewer."
        case .duplicateName:
            "A playlist with that name already exists."
        case .missingEpisodeIdentity:
            "That episode can’t be added to a playlist because it isn’t associated with a Podcast."
        }
    }
}
