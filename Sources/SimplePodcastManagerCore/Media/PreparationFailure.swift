import Foundation

public enum PreparationFailureReason: Equatable, Sendable {
    case other
    case insecureDownloadRequiresPermission
}

public struct PreparationFailure: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var episode: Episode
    public var message: String
    public var reason: PreparationFailureReason

    public var episodeID: String { episode.id }
    public var episodeTitle: String { episode.title }

    public init(
        id: UUID = UUID(),
        episode: Episode,
        message: String,
        reason: PreparationFailureReason = .other
    ) {
        self.id = id
        self.episode = episode
        self.message = message
        self.reason = reason
    }
}
