import Foundation

public struct FeedFetchResult: Equatable, Sendable {
    public var allEpisodes: [Episode]
    public var selectedEpisodes: [Episode]
    public var failures: [FeedFetchFailure]
    public var feedSummaries: [FeedSummary]

    public init(
        allEpisodes: [Episode] = [],
        selectedEpisodes: [Episode],
        failures: [FeedFetchFailure] = [],
        feedSummaries: [FeedSummary] = []
    ) {
        self.allEpisodes = allEpisodes
        self.selectedEpisodes = selectedEpisodes
        self.failures = failures
        self.feedSummaries = feedSummaries
    }
}

public struct FeedSummary: Equatable, Sendable, Identifiable {
    public var id: UUID { subscriptionID }
    public var subscriptionID: UUID
    public var title: String
    public var artworkURL: URL?

    public init(subscriptionID: UUID, title: String, artworkURL: URL? = nil) {
        self.subscriptionID = subscriptionID
        self.title = title
        self.artworkURL = artworkURL
    }
}

public struct FeedFetchFailure: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var subscriptionID: UUID
    public var subscriptionTitle: String
    public var message: String

    public init(
        id: UUID = UUID(),
        subscriptionID: UUID,
        subscriptionTitle: String,
        message: String
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.subscriptionTitle = subscriptionTitle
        self.message = message
    }
}
