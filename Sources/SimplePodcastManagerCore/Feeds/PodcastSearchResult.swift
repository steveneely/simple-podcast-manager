import Foundation

public struct PodcastSearchResult: Equatable, Identifiable, Sendable {
    public let title: String
    public let author: String?
    public let feedURL: URL
    public let artworkURL: URL?
    public let episodeCount: Int?
    public let isExplicit: Bool

    public init(
        title: String,
        author: String? = nil,
        feedURL: URL,
        artworkURL: URL? = nil,
        episodeCount: Int? = nil,
        isExplicit: Bool = false
    ) {
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.episodeCount = episodeCount
        self.isExplicit = isExplicit
    }

    public var id: String {
        FeedURLIdentity.normalized(feedURL)
    }
}
