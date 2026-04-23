import Foundation

public struct DiscoveryResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var author: String?
    public var summary: String?
    public var artworkURL: URL?
    public var feedURL: URL?
    public var source: String

    public init(
        id: String,
        title: String,
        author: String? = nil,
        summary: String? = nil,
        artworkURL: URL? = nil,
        feedURL: URL? = nil,
        source: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.artworkURL = artworkURL
        self.feedURL = feedURL
        self.source = source
    }

    public var isSubscribable: Bool {
        feedURL != nil
    }

    public func makeSubscription(defaultRetentionEpisodeLimit: Int = 3) throws -> FeedSubscription {
        guard let feedURL else {
            throw DiscoveryResultError.missingFeedURL
        }

        return FeedSubscription(
            title: title,
            rssURL: feedURL,
            artworkURL: artworkURL,
            retentionPolicy: .keepLatestEpisodes(defaultRetentionEpisodeLimit)
        )
    }
}

public enum DiscoveryResultError: Error, Equatable, Sendable {
    case missingFeedURL
}
