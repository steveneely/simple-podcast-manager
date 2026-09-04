import Foundation

public struct PodcastActivityState: Codable, Equatable, Sendable {
    public var podcasts: [PodcastActivityEntry]

    public init(podcasts: [PodcastActivityEntry] = []) {
        self.podcasts = podcasts
    }

    private enum CodingKeys: String, CodingKey {
        // Keep the established JSON key for backup compatibility.
        case podcasts = "feeds"
    }
}

public struct PodcastActivityEntry: Codable, Equatable, Sendable {
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

public protocol PodcastActivityStateStore: Sendable {
    func loadPodcastActivityState() throws -> PodcastActivityState
    func savePodcastActivityState(_ state: PodcastActivityState) throws
}
