import Foundation

public struct MediaPreparationService: Sendable {
    private let downloadService: any DownloadService
    private let audioConversionService: any AudioConversionService
    private let workspaceProvider: any TemporaryWorkspaceProviding
    private let maximumConcurrentPreparations: Int

    public init(
        downloadService: any DownloadService = URLSessionDownloadService(),
        audioConversionService: any AudioConversionService = FFmpegAudioConversionService(),
        workspaceProvider: any TemporaryWorkspaceProviding = PersistentMediaWorkspaceProvider(),
        maximumConcurrentPreparations: Int = 3
    ) {
        self.downloadService = downloadService
        self.audioConversionService = audioConversionService
        self.workspaceProvider = workspaceProvider
        self.maximumConcurrentPreparations = max(1, maximumConcurrentPreparations)
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
        var nextEpisodeIndex = 0
        var activeEpisodes: [String: String] = [:]

        await withTaskGroup(of: EpisodePreparationOutcome.self) { group in
            func reportProgress() {
                let activeEpisodeIDs = activeEpisodes.keys.sorted {
                    (activeEpisodes[$0] ?? "").localizedCaseInsensitiveCompare(activeEpisodes[$1] ?? "") == .orderedAscending
                }
                let activeEpisodeTitles = activeEpisodeIDs.compactMap { activeEpisodes[$0] }
                progress?(
                    PreparationProgress(
                        totalCount: episodes.count,
                        completedCount: completedCount,
                        currentEpisodeID: activeEpisodeIDs.first,
                        currentEpisodeTitle: activeEpisodeTitles.first,
                        activeEpisodeIDs: activeEpisodeIDs,
                        activeEpisodeTitles: activeEpisodeTitles
                    )
                )
            }

            func startNextEpisodeIfNeeded() {
                guard nextEpisodeIndex < episodes.count else { return }
                guard activeEpisodes.count < maximumConcurrentPreparations else { return }

                let episode = episodes[nextEpisodeIndex]
                nextEpisodeIndex += 1
                activeEpisodes[episode.id] = episode.title
                reportProgress()

                group.addTask {
                    await prepareEpisode(episode, workspaceURL: workspaceURL, settings: settings)
                }
            }

            for _ in 0..<min(maximumConcurrentPreparations, episodes.count) {
                startNextEpisodeIfNeeded()
            }

            while let outcome = await group.next() {
                activeEpisodes.removeValue(forKey: outcome.episodeID)

                switch outcome.result {
                case .success(let preparedEpisode):
                    preparedEpisodes.append(preparedEpisode)
                case .failure(let failure):
                    failures.append(failure)
                }

                completedCount += 1
                startNextEpisodeIfNeeded()
                reportProgress()
            }
        }

        return MediaPreparationResult(
            preparedEpisodes: preparedEpisodes.sorted {
                $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending
            },
            failures: failures.sorted {
                $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
            },
            workspaceURL: workspaceURL
        )
    }

    private func prepareEpisode(
        _ episode: Episode,
        workspaceURL: URL,
        settings: AppSettings
    ) async -> EpisodePreparationOutcome {
        do {
            let sourceFileURL = try await downloadService.download(episode, into: workspaceURL)
            let preparedEpisode = try await audioConversionService.prepareAudio(
                for: episode,
                sourceFileURL: sourceFileURL,
                in: workspaceURL,
                settings: settings
            )
            return EpisodePreparationOutcome(episodeID: episode.id, result: .success(preparedEpisode))
        } catch {
            return EpisodePreparationOutcome(
                episodeID: episode.id,
                result: .failure(
                    PreparationFailure(
                        episodeID: episode.id,
                        episodeTitle: episode.title,
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            )
        }
    }
}

private struct EpisodePreparationOutcome: Sendable {
    var episodeID: String
    var result: EpisodePreparationResult
}

private enum EpisodePreparationResult: Sendable {
    case success(PreparedEpisode)
    case failure(PreparationFailure)
}
