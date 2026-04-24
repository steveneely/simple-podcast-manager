import Foundation

public struct PreparedEpisode: Codable, Equatable, Sendable, Identifiable {
    public var id: String { episode.id }
    public var episode: Episode
    public var sourceFileURL: URL
    public var preparedFileURL: URL
    public var preparationAction: PreparationAction
    public var preparedAt: Date?

    public init(
        episode: Episode,
        sourceFileURL: URL,
        preparedFileURL: URL,
        preparationAction: PreparationAction,
        preparedAt: Date? = Date()
    ) {
        self.episode = episode
        self.sourceFileURL = sourceFileURL
        self.preparedFileURL = preparedFileURL
        self.preparationAction = preparationAction
        self.preparedAt = preparedAt
    }
}

public enum PreparationAction: String, Codable, Equatable, Sendable {
    case passthroughMP3
    case convertedToMP3
}
