import Foundation

public struct RemovedEpisodeRecord: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var subscriptionID: UUID
    public var episodeID: String?
    public var fileStem: String
    public var episodeTitle: String
    public var publicationDate: Date?
    public var deviceName: String?
    public var removedAt: Date

    public init(
        subscriptionID: UUID,
        episodeID: String?,
        fileStem: String,
        episodeTitle: String,
        publicationDate: Date?,
        deviceName: String?,
        removedAt: Date
    ) {
        self.id = "\(subscriptionID.uuidString.lowercased())::\(fileStem)"
        self.subscriptionID = subscriptionID
        self.episodeID = episodeID
        self.fileStem = fileStem
        self.episodeTitle = episodeTitle
        self.publicationDate = publicationDate
        self.deviceName = deviceName
        self.removedAt = removedAt
    }
}
