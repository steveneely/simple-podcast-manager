import Foundation

public struct DeviceCleanupCandidate: Equatable, Sendable, Identifiable {
    public var id: URL { targetURL.standardizedFileURL }

    public var targetURL: URL
    public var subscriptionID: UUID
    public var podcastTitle: String
    public var episodeTitle: String
    public var publicationDate: Date
    public var fileSizeBytes: Int64

    public init(
        targetURL: URL,
        subscriptionID: UUID,
        podcastTitle: String,
        episodeTitle: String,
        publicationDate: Date,
        fileSizeBytes: Int64
    ) {
        self.targetURL = targetURL
        self.subscriptionID = subscriptionID
        self.podcastTitle = podcastTitle
        self.episodeTitle = episodeTitle
        self.publicationDate = publicationDate
        self.fileSizeBytes = fileSizeBytes
    }
}

public enum DeviceCleanupPolicyError: LocalizedError, Equatable, Sendable {
    case invalidMaximumEpisodesPerPodcast(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMaximumEpisodesPerPodcast:
            return "Choose a supported number of episodes to keep per podcast. No cleanup was planned."
        }
    }
}
