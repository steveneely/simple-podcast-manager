import Foundation

public struct MediaPreparationResult: Equatable, Sendable {
    public var preparedEpisodes: [PreparedEpisode]
    public var failures: [PreparationFailure]
    public var workspaceURL: URL

    public init(
        preparedEpisodes: [PreparedEpisode],
        failures: [PreparationFailure],
        workspaceURL: URL
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.failures = failures
        self.workspaceURL = workspaceURL
    }
}
