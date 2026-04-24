import Foundation

public struct RemovedEpisodeRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subscriptionID: UUID
    public var episodeID: String
    public var episodeTitle: String
    public var publicationDate: Date?
    public var removedAt: Date

    public init(
        subscriptionID: UUID,
        episodeID: String,
        episodeTitle: String,
        publicationDate: Date?,
        removedAt: Date
    ) {
        self.id = "\(subscriptionID.uuidString.lowercased())::\(episodeID)"
        self.subscriptionID = subscriptionID
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.publicationDate = publicationDate
        self.removedAt = removedAt
    }
}
