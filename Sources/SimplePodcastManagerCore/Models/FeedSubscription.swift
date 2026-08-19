import Foundation

public struct FeedSubscription: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var rssURL: URL
    public var artworkURL: URL?
    public var description: String?
    public var isEnabled: Bool
    public var includesInAutomaticDownloads: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        rssURL: URL,
        artworkURL: URL? = nil,
        description: String? = nil,
        isEnabled: Bool = true,
        includesInAutomaticDownloads: Bool = true
    ) {
        self.id = id
        self.title = title
        self.rssURL = rssURL
        self.artworkURL = artworkURL
        self.description = description
        self.isEnabled = isEnabled
        self.includesInAutomaticDownloads = includesInAutomaticDownloads
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case rssURL
        case artworkURL
        case description
        case isEnabled
        case includesInAutomaticDownloads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        rssURL = try container.decode(URL.self, forKey: .rssURL)
        artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        includesInAutomaticDownloads = try container.decodeIfPresent(
            Bool.self,
            forKey: .includesInAutomaticDownloads
        ) ?? true
    }
}
