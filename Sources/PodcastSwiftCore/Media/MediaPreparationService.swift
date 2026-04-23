import Foundation

public struct MediaPreparationService: Sendable {
    private let downloadService: any DownloadService
    private let audioConversionService: any AudioConversionService
    private let workspaceProvider: any TemporaryWorkspaceProviding

    public init(
        downloadService: any DownloadService = URLSessionDownloadService(),
        audioConversionService: any AudioConversionService = FFmpegAudioConversionService(),
        workspaceProvider: any TemporaryWorkspaceProviding = PersistentMediaWorkspaceProvider()
    ) {
        self.downloadService = downloadService
        self.audioConversionService = audioConversionService
        self.workspaceProvider = workspaceProvider
    }

    public func prepareEpisodes(
        _ episodes: [Episode],
        settings: AppSettings,
        progress: (@Sendable (PreparationProgress) -> Void)? = nil
    ) async throws -> MediaPreparationResult {
        let workspaceURL = try workspaceProvider.makeWorkspace()
        var preparedEpisodes: [PreparedEpisode] = []
        var failures: [PreparationFailure] = []
        var completedCount = 0

        for episode in episodes {
            progress?(
                PreparationProgress(
                    totalCount: episodes.count,
                    completedCount: completedCount,
                    currentEpisodeID: episode.id,
                    currentEpisodeTitle: episode.title
                )
            )
            do {
                let sourceFileURL = try await downloadService.download(episode, into: workspaceURL)
                let preparedEpisode = try await audioConversionService.prepareAudio(
                    for: episode,
                    sourceFileURL: sourceFileURL,
                    in: workspaceURL,
                    settings: settings
                )
                preparedEpisodes.append(preparedEpisode)
            } catch {
                failures.append(
                    PreparationFailure(
                        episodeID: episode.id,
                        episodeTitle: episode.title,
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
            completedCount += 1
        }

        progress?(
            PreparationProgress(
                totalCount: episodes.count,
                completedCount: completedCount
            )
        )

        return MediaPreparationResult(
            preparedEpisodes: preparedEpisodes,
            failures: failures,
            workspaceURL: workspaceURL
        )
    }
}
