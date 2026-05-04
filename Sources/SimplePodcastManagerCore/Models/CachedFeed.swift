import Foundation

public struct CachedFeed: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 3

    public var formatVersion: Int
    public var subscriptionID: UUID
    public var rssURL: URL
    public var fetchedAt: Date
    public var etag: String?
    public var lastModified: String?
    public var summary: FeedSummary
    public var episodes: [Episode]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        subscriptionID: UUID,
        rssURL: URL,
        fetchedAt: Date,
        etag: String? = nil,
        lastModified: String? = nil,
        summary: FeedSummary,
        episodes: [Episode]
    ) {
        self.formatVersion = formatVersion
        self.subscriptionID = subscriptionID
        self.rssURL = rssURL
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.summary = summary
        self.episodes = episodes
    }
}
