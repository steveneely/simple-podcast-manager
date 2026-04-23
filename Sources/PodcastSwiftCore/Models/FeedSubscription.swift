import Foundation

public struct FeedSubscription: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var rssURL: URL
    public var podcastFolderName: String?
    public var retentionPolicy: RetentionPolicy
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        rssURL: URL,
        podcastFolderName: String? = nil,
        retentionPolicy: RetentionPolicy = .keepLatestEpisodes(3),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.rssURL = rssURL
        self.podcastFolderName = podcastFolderName
        self.retentionPolicy = retentionPolicy
        self.isEnabled = isEnabled
    }
}
