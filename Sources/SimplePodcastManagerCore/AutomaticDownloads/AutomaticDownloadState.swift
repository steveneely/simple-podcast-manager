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

public struct AutomaticDownloadFeedState: Codable, Equatable, Sendable {
    public var subscriptionID: UUID
    public var rssURL: URL
    public var observedEpisodeIDs: Set<String>
    public var pendingEpisodeIDs: Set<String>

    public init(
        subscriptionID: UUID,
        rssURL: URL,
        observedEpisodeIDs: Set<String> = [],
        pendingEpisodeIDs: Set<String> = []
    ) {
        self.subscriptionID = subscriptionID
        self.rssURL = rssURL
        self.observedEpisodeIDs = observedEpisodeIDs
        self.pendingEpisodeIDs = pendingEpisodeIDs
    }
}

public struct AutomaticDownloadState: Codable, Equatable, Sendable {
    public var feeds: [AutomaticDownloadFeedState]

    public init(feeds: [AutomaticDownloadFeedState] = []) {
        self.feeds = feeds
    }
}
