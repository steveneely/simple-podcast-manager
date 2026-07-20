import Foundation

public struct MediaPreparationResult: Equatable, Sendable {
    public var preparedEpisodes: [PreparedEpisode]
    public var failures: [PreparationFailure]

    public init(
        preparedEpisodes: [PreparedEpisode],
        failures: [PreparationFailure]
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.failures = failures
    }
}
