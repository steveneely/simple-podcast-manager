import Foundation

public struct DownloadedEpisodeRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subscriptionID: UUID
    public var episodeID: String
    public var episodeTitle: String
    public var preparationAction: PreparationAction
    public var downloadedAt: Date

    public init(
        subscriptionID: UUID,
        episodeID: String,
        episodeTitle: String,
        preparationAction: PreparationAction,
        downloadedAt: Date
    ) {
        self.id = "\(subscriptionID.uuidString.lowercased())::\(episodeID)"
        self.subscriptionID = subscriptionID
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.preparationAction = preparationAction
        self.downloadedAt = downloadedAt
    }
}
