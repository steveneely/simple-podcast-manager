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

public enum PodcastPlaylistAutomaticSource: Codable, Equatable, Sendable {
    case allPodcasts
    case selectedPodcasts(Set<PodcastSubscription.ID>)
    case recentlyDownloaded

    public func includesPodcast(_ subscriptionID: PodcastSubscription.ID) -> Bool {
        switch self {
        case .allPodcasts:
            true
        case .selectedPodcasts(let includedPodcastIDs):
            includedPodcastIDs.contains(subscriptionID)
        case .recentlyDownloaded:
            true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case podcastIDs
    }

    private enum Kind: String, Codable {
        case allPodcasts
        case selectedPodcasts
        case recentlyDownloaded
        // Development builds briefly persisted this value before download-based
        // automatic playlists replaced device-sync snapshots.
        case mostRecentSync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allPodcasts:
            self = .allPodcasts
        case .selectedPodcasts:
            self = .selectedPodcasts(
                try container.decode(Set<PodcastSubscription.ID>.self, forKey: .podcastIDs)
            )
        case .recentlyDownloaded, .mostRecentSync:
            self = .recentlyDownloaded
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allPodcasts:
            try container.encode(Kind.allPodcasts, forKey: .kind)
        case .selectedPodcasts(let podcastIDs):
            try container.encode(Kind.selectedPodcasts, forKey: .kind)
            try container.encode(podcastIDs, forKey: .podcastIDs)
        case .recentlyDownloaded:
            try container.encode(Kind.recentlyDownloaded, forKey: .kind)
        }
    }
}

public struct PodcastPlaylistAutomaticRule: Codable, Equatable, Sendable {
    public var source: PodcastPlaylistAutomaticSource
    public var maximumEpisodeCount: Int?

    public init(
        source: PodcastPlaylistAutomaticSource = .allPodcasts,
        maximumEpisodeCount: Int? = nil
    ) {
        self.source = source
        self.maximumEpisodeCount = maximumEpisodeCount
    }
}

public struct PodcastPlaylistAutomaticExclusion: Codable, Equatable, Hashable, Sendable {
    public var subscriptionID: PodcastSubscription.ID
    public var episodeFileStem: String

    public init?(episode: Episode) {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        self.subscriptionID = subscriptionID
        self.episodeFileStem = EpisodeFileName.fileStem(for: episode)
    }

    public init(subscriptionID: PodcastSubscription.ID, episodeFileStem: String) {
        self.subscriptionID = subscriptionID
        self.episodeFileStem = episodeFileStem
    }
}

public struct PodcastPlaylist: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var deviceFileName: String
    public var entries: [PodcastPlaylistEntry]
    public var automaticRule: PodcastPlaylistAutomaticRule?
    public var automaticExclusions: Set<PodcastPlaylistAutomaticExclusion>

    public init(
        id: UUID = UUID(),
        name: String,
        deviceFileName: String? = nil,
        entries: [PodcastPlaylistEntry] = [],
        automaticRule: PodcastPlaylistAutomaticRule? = nil,
        automaticExclusions: Set<PodcastPlaylistAutomaticExclusion> = []
    ) throws {
        let validatedName = try PodcastPlaylistName.validated(name)
        self.id = id
        self.name = validatedName
        self.deviceFileName = deviceFileName ?? PodcastPlaylistName.deviceFileName(for: validatedName)
        self.entries = entries
        self.automaticRule = automaticRule
        self.automaticExclusions = automaticExclusions
    }

    public var automaticallyAddsEpisodes: Bool { automaticRule != nil }

    public func contains(_ episode: Episode) -> Bool {
        guard let id = PodcastPlaylistEpisodeID(episode: episode) else { return false }
        return entries.contains { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case deviceFileName
        case entries
        case automaticRule
        case automaticExclusions
        // Development builds briefly persisted this key before playlists became unified.
        case legacySmartRule = "smartRule"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        deviceFileName = try container.decode(String.self, forKey: .deviceFileName)
        entries = try container.decodeIfPresent([PodcastPlaylistEntry].self, forKey: .entries) ?? []
        automaticRule = try container.decodeIfPresent(
            PodcastPlaylistAutomaticRule.self,
            forKey: .automaticRule
        ) ?? container.decodeIfPresent(
            PodcastPlaylistAutomaticRule.self,
            forKey: .legacySmartRule
        )
        automaticExclusions = try container.decodeIfPresent(
            Set<PodcastPlaylistAutomaticExclusion>.self,
            forKey: .automaticExclusions
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(deviceFileName, forKey: .deviceFileName)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(automaticRule, forKey: .automaticRule)
        try container.encode(automaticExclusions, forKey: .automaticExclusions)
    }
}

public struct PodcastPlaylistLibrary: Codable, Equatable, Sendable {
    public var playlists: [PodcastPlaylist]
    public var deviceStates: [String: PodcastPlaylistDeviceState]
    public var recentlyDownloadedEntries: [PodcastPlaylistEntry]

    public init(
        playlists: [PodcastPlaylist] = [],
        deviceStates: [String: PodcastPlaylistDeviceState] = [:],
        recentlyDownloadedEntries: [PodcastPlaylistEntry] = []
    ) {
        self.playlists = playlists
        self.deviceStates = deviceStates
        self.recentlyDownloadedEntries = recentlyDownloadedEntries
    }

    private enum CodingKeys: String, CodingKey {
        case playlists
        case deviceStates
        case recentlyDownloadedEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try container.decodeIfPresent([PodcastPlaylist].self, forKey: .playlists) ?? []
        let decodedDeviceStates = try container.decodeIfPresent(
            [String: PodcastPlaylistDeviceState].self,
            forKey: .deviceStates
        ) ?? [:]
        deviceStates = decodedDeviceStates

        if container.contains(.recentlyDownloadedEntries) {
            recentlyDownloadedEntries = try container.decode(
                [PodcastPlaylistEntry].self,
                forKey: .recentlyDownloadedEntries
            )
        } else {
            var seenEntryIDs: Set<PodcastPlaylistEpisodeID> = []
            let migratedEntries = decodedDeviceStates.keys.sorted().flatMap { deviceID in
                decodedDeviceStates[deviceID]?.mostRecentSyncEntries ?? []
            }.filter { seenEntryIDs.insert($0.id).inserted }
            recentlyDownloadedEntries = migratedEntries
        }
    }
}

public struct PodcastPlaylistDeviceState: Codable, Equatable, Sendable {
    public var ownedDeviceFileNames: Set<String>
    public var pendingDeletedDeviceFileNames: Set<String>
    public var playlistDirectoryPath: String?
    // Keep this temporary development-build key decodable so its episode
    // snapshots can migrate into PodcastPlaylistLibrary.recentlyDownloadedEntries.
    public var mostRecentSyncEntries: [PodcastPlaylistEntry]

    public init(
        ownedDeviceFileNames: Set<String> = [],
        pendingDeletedDeviceFileNames: Set<String> = [],
        playlistDirectoryPath: String? = nil,
        mostRecentSyncEntries: [PodcastPlaylistEntry] = []
    ) {
        self.ownedDeviceFileNames = ownedDeviceFileNames
        self.pendingDeletedDeviceFileNames = pendingDeletedDeviceFileNames
        self.playlistDirectoryPath = playlistDirectoryPath
        self.mostRecentSyncEntries = mostRecentSyncEntries
    }

    private enum CodingKeys: String, CodingKey {
        case ownedDeviceFileNames
        case pendingDeletedDeviceFileNames
        case playlistDirectoryPath
        case mostRecentSyncEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownedDeviceFileNames = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .ownedDeviceFileNames
        ) ?? []
        pendingDeletedDeviceFileNames = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .pendingDeletedDeviceFileNames
        ) ?? []
        playlistDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .playlistDirectoryPath
        )
        mostRecentSyncEntries = try container.decodeIfPresent(
            [PodcastPlaylistEntry].self,
            forKey: .mostRecentSyncEntries
        ) ?? []
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
    case automaticPlaylistNeedsPodcast
    case unsupportedAutomaticPlaylistSource
    case invalidAutomaticPlaylistLimit

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
        case .automaticPlaylistNeedsPodcast:
            "Select at least one Podcast to add episodes automatically."
        case .unsupportedAutomaticPlaylistSource:
            "This older automatic playlist rule must be replaced by selecting Podcasts."
        case .invalidAutomaticPlaylistLimit:
            "The automatic episode limit must be greater than zero."
        }
    }
}
