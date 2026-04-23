import Foundation

public struct Episode: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var subscriptionID: UUID?
    public var podcastTitle: String
    public var title: String
    public var publicationDate: Date?
    public var enclosureURL: URL
    public var sourceFeedURL: URL

    public init(
        id: String,
        subscriptionID: UUID? = nil,
        podcastTitle: String,
        title: String,
        publicationDate: Date? = nil,
        enclosureURL: URL,
        sourceFeedURL: URL
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.podcastTitle = podcastTitle
        self.title = title
        self.publicationDate = publicationDate
        self.enclosureURL = enclosureURL
        self.sourceFeedURL = sourceFeedURL
    }
}
