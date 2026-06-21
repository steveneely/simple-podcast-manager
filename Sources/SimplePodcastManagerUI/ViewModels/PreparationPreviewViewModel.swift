import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PreparationPreviewViewModel {
    public private(set) var preparedEpisodes: [PreparedEpisode]
    public private(set) var downloadedEpisodes: [DownloadedEpisodeRecord]
    public private(set) var failures: [PreparationFailure]
    public private(set) var workspaceURL: URL?
    public private(set) var progress: PreparationProgress?
    public private(set) var activeDownloads: [PreparationDownloadStatus]
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedPreparedEpisodes: Bool

    private let service: MediaPreparationService
    private let store: any PreparedEpisodeStore
    private let downloadedEpisodeStore: any DownloadedEpisodeStore
    private var preparingEpisodesByID: [String: Episode]
    private var runningDownloadIDsByBatchID: [UUID: Set<String>]

    public init(
        service: MediaPreparationService = MediaPreparationService(),
        store: any PreparedEpisodeStore = JSONPreparedEpisodeStore(fileURL: JSONPreparedEpisodeStore.defaultFileURL()),
        downloadedEpisodeStore: any DownloadedEpisodeStore = JSONDownloadedEpisodeStore(fileURL: JSONDownloadedEpisodeStore.defaultFileURL())
    ) {
        self.service = service
        self.store = store
        self.downloadedEpisodeStore = downloadedEpisodeStore
        self.preparedEpisodes = []
        self.downloadedEpisodes = []
        self.failures = []
        self.workspaceURL = nil
        self.progress = nil
        self.activeDownloads = []
        self.lastErrorMessage = nil
        self.hasLoadedPreparedEpisodes = false
        self.preparingEpisodesByID = [:]
        self.runningDownloadIDsByBatchID = [:]
    }

    public var hasResults: Bool {
        !preparedEpisodes.isEmpty || !failures.isEmpty
    }

    public var isPreparing: Bool {
        !activeDownloads.isEmpty
    }

    public func prepare(_ episodes: [Episode], settings: AppSettings) async {
        let episodesToPrepare = episodes.filter {
            preparedEpisode(for: $0) == nil && preparingEpisodesByID[$0.id] == nil
        }
        guard !episodesToPrepare.isEmpty else { return }

        let batchID = UUID()
        beginPreparing(episodesToPrepare, batchID: batchID)
        progress = PreparationProgress(
            totalCount: episodesToPrepare.count,
            completedCount: 0,
            activeEpisodeIDs: episodesToPrepare.map(\.id),
            activeEpisodeTitles: episodesToPrepare.map(\.title)
        )
        defer {
            finishPreparing(episodesToPrepare, batchID: batchID)
            if !isPreparing {
                progress = nil
            }
        }

        do {
            let result = try await service.prepareEpisodes(
                episodesToPrepare,
                settings: settings,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.runningDownloadIDsByBatchID[batchID] = Set(progress.activeEpisodeIDs)
                        self?.refreshActiveDownloads()
                        self?.progress = progress
                    }
                }
            )
            merge(result)
            recordDownloadedEpisodes(result.preparedEpisodes)
            persistPreparedEpisodes()
            persistDownloadedEpisodes()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func isPreparing(_ episode: Episode) -> Bool {
        preparingEpisodesByID[episode.id] != nil
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
            self.downloadedEpisodes = try downloadedEpisodeStore.loadDownloadedEpisodes().sorted {
                if $0.downloadedAt != $1.downloadedAt {
                    return $0.downloadedAt > $1.downloadedAt
                }
                return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
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

    public func downloadedRecord(for episode: Episode) -> DownloadedEpisodeRecord? {
        guard let subscriptionID = episode.subscriptionID else { return nil }
        return downloadedEpisodes.first(where: {
            $0.subscriptionID == subscriptionID && $0.episodeID == episode.id
        })
    }

    public func removePreparedEpisode(for episode: Episode) {
        guard let existingPreparedEpisode = preparedEpisode(for: episode) else { return }

        removeFiles(for: existingPreparedEpisode)
        preparedEpisodes.removeAll(where: { $0.episode.id == episode.id })
        failures.removeAll(where: { $0.episodeID == episode.id })
        persistPreparedEpisodes()
    }

    public func removeAllPreparedEpisodes() {
        for preparedEpisode in preparedEpisodes {
            removeFiles(for: preparedEpisode)
        }
        preparedEpisodes = []
        failures = []
        workspaceURL = nil
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

    private func recordDownloadedEpisodes(_ preparedEpisodes: [PreparedEpisode]) {
        guard !preparedEpisodes.isEmpty else { return }

        var recordsByID = Dictionary(uniqueKeysWithValues: downloadedEpisodes.map { ($0.id, $0) })
        for preparedEpisode in preparedEpisodes {
            guard let subscriptionID = preparedEpisode.episode.subscriptionID else { continue }
            let record = DownloadedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: preparedEpisode.episode.id,
                episodeTitle: preparedEpisode.episode.title,
                preparationAction: preparedEpisode.preparationAction,
                downloadedAt: preparedEpisode.preparedAt
            )
            recordsByID[record.id] = record
        }

        downloadedEpisodes = recordsByID.values.sorted {
            if $0.downloadedAt != $1.downloadedAt {
                return $0.downloadedAt > $1.downloadedAt
            }
            return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
        }
    }

    private func persistDownloadedEpisodes() {
        do {
            try downloadedEpisodeStore.saveDownloadedEpisodes(downloadedEpisodes)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeFiles(for preparedEpisode: PreparedEpisode) {
        try? FileManager.default.removeItem(at: preparedEpisode.preparedFileURL)
        if preparedEpisode.preparedFileURL != preparedEpisode.sourceFileURL {
            try? FileManager.default.removeItem(at: preparedEpisode.sourceFileURL)
        }
    }

    private func beginPreparing(_ episodes: [Episode], batchID: UUID) {
        for episode in episodes {
            preparingEpisodesByID[episode.id] = episode
        }
        runningDownloadIDsByBatchID[batchID] = []
        refreshActiveDownloads()
    }

    private func finishPreparing(_ episodes: [Episode], batchID: UUID) {
        for episode in episodes {
            preparingEpisodesByID.removeValue(forKey: episode.id)
        }
        runningDownloadIDsByBatchID.removeValue(forKey: batchID)
        refreshActiveDownloads()
    }

    private func refreshActiveDownloads() {
        let runningIDs = Set(runningDownloadIDsByBatchID.values.flatMap { $0 })
        activeDownloads = preparingEpisodesByID.values
            .map { episode in
                PreparationDownloadStatus(
                    episodeID: episode.id,
                    episodeTitle: episode.title,
                    state: runningIDs.contains(episode.id) ? .downloading : .queued
                )
            }
            .sorted {
                if $0.state != $1.state {
                    return $0.state == .downloading
                }
                return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
            }
    }
}

public struct PreparationDownloadStatus: Identifiable, Equatable, Sendable {
    public var episodeID: String
    public var episodeTitle: String
    public var state: PreparationDownloadState

    public var id: String {
        episodeID
    }
}

public enum PreparationDownloadState: String, Equatable, Sendable {
    case queued
    case downloading
}
