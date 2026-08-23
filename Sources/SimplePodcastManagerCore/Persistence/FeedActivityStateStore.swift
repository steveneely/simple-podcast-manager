import Foundation

public struct FeedActivityState: Codable, Equatable, Sendable {
    public var feeds: [FeedActivityFeedState]

    public init(feeds: [FeedActivityFeedState] = []) {
        self.feeds = feeds
    }
}

public struct FeedActivityFeedState: Codable, Equatable, Sendable {
    public var subscriptionID: UUID
    public var rssURL: URL
    public var observedEpisodeIDs: [String]
    public var newEpisodeIDs: Set<String>
    public var newestPublicationDate: Date?

    public init(
        subscriptionID: UUID,
        rssURL: URL,
        observedEpisodeIDs: [String] = [],
        newEpisodeIDs: Set<String> = [],
        newestPublicationDate: Date? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.rssURL = rssURL
        self.observedEpisodeIDs = observedEpisodeIDs
        self.newEpisodeIDs = newEpisodeIDs
        self.newestPublicationDate = newestPublicationDate
    }
}

public protocol FeedActivityStateStore: Sendable {
    func loadFeedActivityState() throws -> FeedActivityState
    func saveFeedActivityState(_ state: FeedActivityState) throws
}
