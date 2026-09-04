import Foundation

public struct AutomaticDownloadEpisodeID: Hashable, Sendable {
    public var subscriptionID: UUID
    public var episodeID: String

    public init(subscriptionID: UUID, episodeID: String) {
        self.subscriptionID = subscriptionID
        self.episodeID = episodeID
    }

    public init?(_ episode: Episode) {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        self.init(subscriptionID: subscriptionID, episodeID: episode.id)
    }
}

public struct AutomaticDownloadPodcastState: Codable, Equatable, Sendable {
    public var subscriptionID: UUID
    public var rssURL: URL
    public var observedEpisodeIDs: [String]
    public var pendingEpisodeIDs: Set<String>

    public init(
        subscriptionID: UUID,
        rssURL: URL,
        observedEpisodeIDs: [String] = [],
        pendingEpisodeIDs: Set<String> = []
    ) {
        self.subscriptionID = subscriptionID
        self.rssURL = rssURL
        self.observedEpisodeIDs = observedEpisodeIDs
        self.pendingEpisodeIDs = pendingEpisodeIDs
    }
}

public struct AutomaticDownloadState: Codable, Equatable, Sendable {
    public var podcasts: [AutomaticDownloadPodcastState]

    public init(podcasts: [AutomaticDownloadPodcastState] = []) {
        self.podcasts = podcasts
    }

    private enum CodingKeys: String, CodingKey {
        // Keep the established JSON key for one-time legacy-state imports.
        case podcasts = "feeds"
    }
}
