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

    enum CodingKeys: String, CodingKey {
        case id
        case subscriptionID
        case episodeID
        case fileStem
        case episodeTitle
        case publicationDate
        case deviceName
        case removedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.subscriptionID = try container.decode(UUID.self, forKey: .subscriptionID)
        self.episodeID = try container.decodeIfPresent(String.self, forKey: .episodeID)
        self.episodeTitle = try container.decode(String.self, forKey: .episodeTitle)
        self.fileStem = try container.decodeIfPresent(String.self, forKey: .fileStem)
            ?? episodeID
            ?? episodeTitle
        self.publicationDate = try container.decodeIfPresent(Date.self, forKey: .publicationDate)
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        self.removedAt = try container.decode(Date.self, forKey: .removedAt)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(subscriptionID.uuidString.lowercased())::\(fileStem)"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subscriptionID, forKey: .subscriptionID)
        try container.encodeIfPresent(episodeID, forKey: .episodeID)
        try container.encode(fileStem, forKey: .fileStem)
        try container.encode(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(publicationDate, forKey: .publicationDate)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encode(removedAt, forKey: .removedAt)
    }
}
