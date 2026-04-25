import Foundation

public struct CachedFeed: Codable, Equatable, Sendable {
    public var subscriptionID: UUID
    public var rssURL: URL
    public var fetchedAt: Date
    public var etag: String?
    public var lastModified: String?
    public var summary: FeedSummary
    public var episodes: [Episode]

    public init(
        subscriptionID: UUID,
        rssURL: URL,
        fetchedAt: Date,
        etag: String? = nil,
        lastModified: String? = nil,
        summary: FeedSummary,
        episodes: [Episode]
    ) {
        self.subscriptionID = subscriptionID
        self.rssURL = rssURL
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.summary = summary
        self.episodes = episodes
    }
}
