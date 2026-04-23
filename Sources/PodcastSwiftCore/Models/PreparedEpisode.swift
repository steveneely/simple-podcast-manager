import Foundation

public struct PreparedEpisode: Equatable, Sendable, Identifiable {
    public var id: String { episode.id }
    public var episode: Episode
    public var sourceFileURL: URL
    public var preparedFileURL: URL
    public var preparationAction: PreparationAction

    public init(
        episode: Episode,
        sourceFileURL: URL,
        preparedFileURL: URL,
        preparationAction: PreparationAction
    ) {
        self.episode = episode
        self.sourceFileURL = sourceFileURL
        self.preparedFileURL = preparedFileURL
        self.preparationAction = preparationAction
    }
}

public enum PreparationAction: Equatable, Sendable {
    case passthroughMP3
    case convertedToMP3
}
