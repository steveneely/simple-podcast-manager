import Foundation

public struct EpisodeStateStartupSnapshot: Sendable {
    public let preparedEpisodes: [PreparedEpisode]
    public let downloadedEpisodes: [DownloadedEpisodeRecord]
    public let removedEpisodes: [RemovedEpisodeRecord]
    public let automaticDownloadState: AutomaticDownloadState
    public let feedActivityState: FeedActivityState

    public init(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord],
        automaticDownloadState: AutomaticDownloadState,
        feedActivityState: FeedActivityState
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.downloadedEpisodes = downloadedEpisodes
        self.removedEpisodes = removedEpisodes
        self.automaticDownloadState = automaticDownloadState
        self.feedActivityState = feedActivityState
    }
}

public protocol EpisodeStateStartupLoading: Sendable {
    func loadStartupSnapshot() throws -> EpisodeStateStartupSnapshot
}
