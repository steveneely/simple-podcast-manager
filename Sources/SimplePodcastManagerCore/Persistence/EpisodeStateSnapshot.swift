import Foundation

public struct EpisodeStateSnapshot: Sendable {
    public let preparedEpisodes: [PreparedEpisode]
    public let downloadedEpisodes: [DownloadedEpisodeRecord]
    public let removedEpisodes: [RemovedEpisodeRecord]
    public let automaticDownloadState: AutomaticDownloadState
    public let podcastActivityState: PodcastActivityState
    public let podcastPlaylistLibrary: PodcastPlaylistLibrary

    public init(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord],
        automaticDownloadState: AutomaticDownloadState,
        podcastActivityState: PodcastActivityState,
        podcastPlaylistLibrary: PodcastPlaylistLibrary = PodcastPlaylistLibrary()
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.downloadedEpisodes = downloadedEpisodes
        self.removedEpisodes = removedEpisodes
        self.automaticDownloadState = automaticDownloadState
        self.podcastActivityState = podcastActivityState
        self.podcastPlaylistLibrary = podcastPlaylistLibrary
    }
}

public protocol EpisodeStateLoading: Sendable {
    func loadEpisodeStateSnapshot() throws -> EpisodeStateSnapshot
}
