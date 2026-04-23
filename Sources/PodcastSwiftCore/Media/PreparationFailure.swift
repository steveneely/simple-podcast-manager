import Foundation

public struct PreparationFailure: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var episodeID: String
    public var episodeTitle: String
    public var message: String

    public init(
        id: UUID = UUID(),
        episodeID: String,
        episodeTitle: String,
        message: String
    ) {
        self.id = id
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.message = message
    }
}
