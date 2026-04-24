import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PreparationPreviewViewModel {
    public private(set) var preparedEpisodes: [PreparedEpisode]
    public private(set) var failures: [PreparationFailure]
    public private(set) var workspaceURL: URL?
    public private(set) var progress: PreparationProgress?
    public private(set) var isPreparing: Bool
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedPreparedEpisodes: Bool

    private let service: MediaPreparationService
    private let store: any PreparedEpisodeStore

    public init(
        service: MediaPreparationService = MediaPreparationService(),
        store: any PreparedEpisodeStore = JSONPreparedEpisodeStore(fileURL: JSONPreparedEpisodeStore.defaultFileURL())
    ) {
        self.service = service
        self.store = store
        self.preparedEpisodes = []
        self.failures = []
        self.workspaceURL = nil
        self.progress = nil
        self.isPreparing = false
        self.lastErrorMessage = nil
        self.hasLoadedPreparedEpisodes = false
    }

    public var hasResults: Bool {
        !preparedEpisodes.isEmpty || !failures.isEmpty
    }

    public func prepare(_ episodes: [Episode], settings: AppSettings) async {
        let episodesToPrepare = episodes.filter { preparedEpisode(for: $0) == nil }
        guard !episodesToPrepare.isEmpty else { return }

        isPreparing = true
        progress = PreparationProgress(totalCount: episodesToPrepare.count, completedCount: 0)
        defer {
            isPreparing = false
            progress = nil
        }

        do {
            let result = try await service.prepareEpisodes(
                episodesToPrepare,
                settings: settings,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.progress = progress
                    }
                }
            )
            merge(result)
            persistPreparedEpisodes()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadPersistedPreparedEpisodes() {
        do {
            let persistedEpisodes = try store.loadPreparedEpisodes()
            let existingPreparedEpisodes = persistedEpisodes.filter {
                FileManager.default.fileExists(atPath: $0.preparedFileURL.path)
            }
            self.preparedEpisodes = existingPreparedEpisodes.sorted {
                $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending
            }
            self.workspaceURL = existingPreparedEpisodes.first?.preparedFileURL.deletingLastPathComponent()
            self.hasLoadedPreparedEpisodes = true
            self.lastErrorMessage = nil

            if existingPreparedEpisodes.count != persistedEpisodes.count {
                persistPreparedEpisodes()
            }
        } catch {
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func preparedEpisode(for episode: Episode) -> PreparedEpisode? {
        preparedEpisodes.first(where: { $0.episode.id == episode.id })
    }

    public func removePreparedEpisode(for episode: Episode) {
        guard let existingPreparedEpisode = preparedEpisode(for: episode) else { return }

        try? FileManager.default.removeItem(at: existingPreparedEpisode.preparedFileURL)
        if existingPreparedEpisode.preparedFileURL != existingPreparedEpisode.sourceFileURL {
            try? FileManager.default.removeItem(at: existingPreparedEpisode.sourceFileURL)
        }

        preparedEpisodes.removeAll(where: { $0.episode.id == episode.id })
        failures.removeAll(where: { $0.episodeID == episode.id })
        persistPreparedEpisodes()
    }

    private func merge(_ result: MediaPreparationResult) {
        workspaceURL = result.workspaceURL

        var mergedPreparedEpisodes = Dictionary(uniqueKeysWithValues: preparedEpisodes.map { ($0.episode.id, $0) })
        for preparedEpisode in result.preparedEpisodes {
            mergedPreparedEpisodes[preparedEpisode.episode.id] = preparedEpisode
        }
        preparedEpisodes = mergedPreparedEpisodes.values.sorted { $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending }

        var mergedFailures = Dictionary(uniqueKeysWithValues: failures.map { ($0.episodeID, $0) })
        for failure in result.failures {
            mergedFailures[failure.episodeID] = failure
        }
        failures = mergedFailures.values.sorted { $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending }
    }

    private func persistPreparedEpisodes() {
        do {
            try store.savePreparedEpisodes(preparedEpisodes)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
