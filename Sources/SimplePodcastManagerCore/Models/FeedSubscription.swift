import Foundation

public struct FeedSubscription: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var rssURL: URL
    public var artworkURL: URL?
    public var description: String?
    public var retentionPolicy: RetentionPolicy
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        rssURL: URL,
        artworkURL: URL? = nil,
        description: String? = nil,
        retentionPolicy: RetentionPolicy = .keepLatestEpisodes(.max),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.rssURL = rssURL
        self.artworkURL = artworkURL
        self.description = description
        self.retentionPolicy = retentionPolicy
        self.isEnabled = isEnabled
    }
}
