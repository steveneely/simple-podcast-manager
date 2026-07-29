import Foundation

public struct PreparationFailure: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var episode: Episode
    public var message: String

    public var episodeID: String { episode.id }
    public var episodeTitle: String { episode.title }

    public init(
        id: UUID = UUID(),
        episode: Episode,
        message: String
    ) {
        self.id = id
        self.episode = episode
        self.message = message
    }
}
