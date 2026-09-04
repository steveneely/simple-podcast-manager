import Foundation

public struct EpisodeStateStartupSnapshot: Sendable {
    public let preparedEpisodes: [PreparedEpisode]
    public let downloadedEpisodes: [DownloadedEpisodeRecord]
    public let removedEpisodes: [RemovedEpisodeRecord]
    public let automaticDownloadState: AutomaticDownloadState
    public let podcastActivityState: PodcastActivityState

    public init(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord],
        automaticDownloadState: AutomaticDownloadState,
        podcastActivityState: PodcastActivityState
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.downloadedEpisodes = downloadedEpisodes
        self.removedEpisodes = removedEpisodes
        self.automaticDownloadState = automaticDownloadState
        self.podcastActivityState = podcastActivityState
    }
}

public protocol EpisodeStateStartupLoading: Sendable {
    func loadStartupSnapshot() throws -> EpisodeStateStartupSnapshot
}
