import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PreparationPreviewViewModel {
    public private(set) var preparedEpisodes: [PreparedEpisode]
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedPreparedEpisodes: Bool

    private let service: MediaPreparationService
    private let store: any PreparedEpisodeStore
    private let downloadedEpisodeStore: any DownloadedEpisodeStore
    private let fileDeleter: any PreparedMediaFileDeleting
    private var downloadedEpisodes: [DownloadedEpisodeRecord]
    private var failures: [PreparationFailure]
    private var preparingEpisodesByID: [EpisodePreparationID: Episode]
    private var preparedEpisodesByID: [EpisodePreparationID: PreparedEpisode]
    private var downloadedEpisodesByID: [EpisodePreparationID: DownloadedEpisodeRecord]
    private var failuresByID: [EpisodePreparationID: PreparationFailure]

    public convenience init(
        service: MediaPreparationService = MediaPreparationService(),
        store: any PreparedEpisodeStore = SQLiteEpisodeStore.shared,
        downloadedEpisodeStore: any DownloadedEpisodeStore = SQLiteEpisodeStore.shared
    ) {
        self.init(
            service: service,
            store: store,
            downloadedEpisodeStore: downloadedEpisodeStore,
            fileDeleter: LocalPreparedMediaFileDeleter()
        )
    }

    init(
        service: MediaPreparationService,
        store: any PreparedEpisodeStore,
        downloadedEpisodeStore: any DownloadedEpisodeStore,
        fileDeleter: any PreparedMediaFileDeleting
    ) {
        self.service = service
        self.store = store
        self.downloadedEpisodeStore = downloadedEpisodeStore
        self.fileDeleter = fileDeleter
        self.preparedEpisodes = []
        self.downloadedEpisodes = []
        self.failures = []
        self.lastErrorMessage = nil
        self.hasLoadedPreparedEpisodes = false
        self.preparingEpisodesByID = [:]
        self.preparedEpisodesByID = [:]
        self.downloadedEpisodesByID = [:]
        self.failuresByID = [:]
    }

    public var isPreparing: Bool {
        !preparingEpisodesByID.isEmpty
    }

    public var preparingEpisodeCount: Int {
        preparingEpisodesByID.count
    }

    public var downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID> {
        Set(downloadedEpisodes.map {
            AutomaticDownloadEpisodeID(subscriptionID: $0.subscriptionID, episodeID: $0.episodeID)
        })
    }

    public func prepare(_ episodes: [Episode], settings: AppSettings) async {
        let episodesToPrepare = episodes.filter {
            preparedEpisode(for: $0) == nil && preparingEpisodesByID[EpisodePreparationID($0)] == nil
        }
        guard !episodesToPrepare.isEmpty else { return }

        beginPreparing(episodesToPrepare)
        defer {
            finishPreparing(episodesToPrepare)
        }

        do {
            let result = try await service.prepareEpisodes(episodesToPrepare, settings: settings)
            merge(result)
            let downloadedRecords = recordDownloadedEpisodes(result.preparedEpisodes)
            lastErrorMessage = nil
            persistNewPreparedEpisodes(result.preparedEpisodes)
            persistNewDownloadedEpisodes(downloadedRecords)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            mergeFailures(for: episodesToPrepare, message: message)
            lastErrorMessage = nil
        }
    }

    public func isPreparing(_ episode: Episode) -> Bool {
        preparingEpisodesByID[EpisodePreparationID(episode)] != nil
    }

    public func loadPersistedPreparedEpisodes() async {
        do {
            let store = self.store
            let downloadedEpisodeStore = self.downloadedEpisodeStore
            let (persistedEpisodes, downloadedEpisodes) = try await Task.detached {
                try (store.loadPreparedEpisodes(), downloadedEpisodeStore.loadDownloadedEpisodes())
            }.value
            try await applyPersistedState(
                preparedEpisodes: persistedEpisodes,
                downloadedEpisodes: downloadedEpisodes
            )
        } catch {
            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func applyPersistedState(
        preparedEpisodes persistedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord]
    ) async throws {
        let existingPreparedEpisodes = await Task.detached(priority: .userInitiated) {
            persistedEpisodes.filter { FileManager.default.fileExists(atPath: $0.preparedFileURL.path) }
        }.value
        self.preparedEpisodes = existingPreparedEpisodes.sorted {
            $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending
        }
        self.downloadedEpisodes = downloadedEpisodes.sorted {
            if $0.downloadedAt != $1.downloadedAt { return $0.downloadedAt > $1.downloadedAt }
            return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
        }
        rebuildIndexes()
        hasLoadedPreparedEpisodes = true
        lastErrorMessage = nil

        if existingPreparedEpisodes.count != persistedEpisodes.count {
            let store = self.store
            try await Task.detached { try store.savePreparedEpisodes(existingPreparedEpisodes) }.value
        }
    }

    public func preparedEpisode(for episode: Episode) -> PreparedEpisode? {
        preparedEpisodesByID[EpisodePreparationID(episode)]
    }

    public func downloadedRecord(for episode: Episode) -> DownloadedEpisodeRecord? {
        downloadedEpisodesByID[EpisodePreparationID(episode)]
    }

    public func failure(for episode: Episode) -> PreparationFailure? {
        failuresByID[EpisodePreparationID(episode)]
    }

    public func requiresInsecureDownloadPermission(for episode: Episode) -> Bool {
        failure(for: episode)?.reason == .insecureDownloadRequiresPermission
    }

    public func removePreparedEpisode(for episode: Episode) async {
        guard let existingPreparedEpisode = preparedEpisode(for: episode) else { return }

        do {
            try await removeFiles(for: existingPreparedEpisode)
        } catch {
            lastErrorMessage = deletionErrorMessage(for: existingPreparedEpisode, error: error)
            return
        }

        let episodeID = EpisodePreparationID(episode)
        preparedEpisodes.removeAll(where: { EpisodePreparationID($0.episode) == episodeID })
        failures.removeAll(where: { EpisodePreparationID($0.episode) == episodeID })
        rebuildIndexes()
        lastErrorMessage = await persistPreparedEpisodes()
    }

    public func removeAllPreparedEpisodes() async {
        var removedEpisodeIDs: Set<EpisodePreparationID> = []
        var deletionErrors: [String] = []

        for preparedEpisode in preparedEpisodes {
            do {
                try await removeFiles(for: preparedEpisode)
                removedEpisodeIDs.insert(EpisodePreparationID(preparedEpisode.episode))
            } catch {
                deletionErrors.append(deletionErrorMessage(for: preparedEpisode, error: error))
            }
        }

        preparedEpisodes.removeAll {
            removedEpisodeIDs.contains(EpisodePreparationID($0.episode))
        }
        failures.removeAll {
            removedEpisodeIDs.contains(EpisodePreparationID($0.episode))
        }
        rebuildIndexes()
        if let persistenceError = await persistPreparedEpisodes() {
            deletionErrors.append(persistenceError)
        }
        lastErrorMessage = deletionErrors.isEmpty ? nil : deletionErrors.joined(separator: "\n")
    }

    private func merge(_ result: MediaPreparationResult) {
        var mergedPreparedEpisodes = Dictionary(
            uniqueKeysWithValues: preparedEpisodes.map { (EpisodePreparationID($0.episode), $0) }
        )
        for preparedEpisode in result.preparedEpisodes {
            mergedPreparedEpisodes[EpisodePreparationID(preparedEpisode.episode)] = preparedEpisode
        }
        preparedEpisodes = mergedPreparedEpisodes.values.sorted { $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending }

        let successfulEpisodeIDs = Set(result.preparedEpisodes.map { EpisodePreparationID($0.episode) })
        failures.removeAll { failure in
            successfulEpisodeIDs.contains(EpisodePreparationID(failure.episode))
        }
        mergeFailures(result.failures)
        rebuildIndexes()
    }

    private func mergeFailures(for episodes: [Episode], message: String) {
        mergeFailures(episodes.map { PreparationFailure(episode: $0, message: message) })
    }

    private func mergeFailures(_ newFailures: [PreparationFailure]) {
        var failuresByEpisodeID = Dictionary(uniqueKeysWithValues: failures.map {
            (EpisodePreparationID($0.episode), $0)
        })
        for failure in newFailures {
            failuresByEpisodeID[EpisodePreparationID(failure.episode)] = failure
        }
        failures = failuresByEpisodeID.values.sorted {
            $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
        }
        rebuildIndexes()
    }

    private func persistPreparedEpisodes() async -> String? {
        let store = self.store
        let preparedEpisodes = self.preparedEpisodes
        do {
            try await Task.detached(priority: .userInitiated) {
                try store.savePreparedEpisodes(preparedEpisodes)
            }.value
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func persistNewPreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) {
        do {
            try store.mergePreparedEpisodes(preparedEpisodes)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recordDownloadedEpisodes(_ preparedEpisodes: [PreparedEpisode]) -> [DownloadedEpisodeRecord] {
        guard !preparedEpisodes.isEmpty else { return [] }

        var recordsByID = Dictionary(uniqueKeysWithValues: downloadedEpisodes.map { ($0.id, $0) })
        var newRecords: [DownloadedEpisodeRecord] = []
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
            newRecords.append(record)
        }

        downloadedEpisodes = recordsByID.values.sorted {
            if $0.downloadedAt != $1.downloadedAt {
                return $0.downloadedAt > $1.downloadedAt
            }
            return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedAscending
        }
        rebuildIndexes()
        return newRecords
    }

    private func rebuildIndexes() {
        preparedEpisodesByID = Dictionary(uniqueKeysWithValues: preparedEpisodes.map {
            (EpisodePreparationID($0.episode), $0)
        })
        downloadedEpisodesByID = Dictionary(uniqueKeysWithValues: downloadedEpisodes.map {
            (EpisodePreparationID(subscriptionID: $0.subscriptionID, episodeID: $0.episodeID), $0)
        })
        failuresByID = Dictionary(uniqueKeysWithValues: failures.map {
            (EpisodePreparationID($0.episode), $0)
        })
    }

    private func persistNewDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) {
        do {
            try downloadedEpisodeStore.mergeDownloadedEpisodes(downloadedEpisodes)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeFiles(for preparedEpisode: PreparedEpisode) async throws {
        let fileDeleter = self.fileDeleter
        try await Task.detached(priority: .userInitiated) {
            let preparedFileURL = preparedEpisode.preparedFileURL.standardizedFileURL
            let sourceFileURL = preparedEpisode.sourceFileURL.standardizedFileURL
            let fileURLs = preparedFileURL == sourceFileURL
                ? [preparedFileURL]
                : [preparedFileURL, sourceFileURL]

            for fileURL in fileURLs where fileDeleter.fileExists(at: fileURL) {
                try fileDeleter.removeItem(at: fileURL)
            }
        }.value
    }

    private func deletionErrorMessage(for preparedEpisode: PreparedEpisode, error: any Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "Could not delete the downloaded files for \"\(preparedEpisode.episode.title)\": \(detail)"
    }

    private func beginPreparing(_ episodes: [Episode]) {
        let episodeIDs = Set(episodes.map(EpisodePreparationID.init))
        failures.removeAll { episodeIDs.contains(EpisodePreparationID($0.episode)) }
        rebuildIndexes()
        for episode in episodes {
            preparingEpisodesByID[EpisodePreparationID(episode)] = episode
        }
    }

    private func finishPreparing(_ episodes: [Episode]) {
        for episode in episodes {
            preparingEpisodesByID.removeValue(forKey: EpisodePreparationID(episode))
        }
    }
}

protocol PreparedMediaFileDeleting: Sendable {
    func fileExists(at url: URL) -> Bool
    func removeItem(at url: URL) throws
}

private struct LocalPreparedMediaFileDeleter: PreparedMediaFileDeleting {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

private enum EpisodePreparationID: Hashable {
    case subscription(UUID, episodeID: String)
    case feed(URL, episodeID: String)

    init(_ episode: Episode) {
        if let subscriptionID = episode.subscriptionID {
            self = .subscription(subscriptionID, episodeID: episode.id)
        } else {
            self = .feed(episode.sourceFeedURL, episodeID: episode.id)
        }
    }

    init(subscriptionID: UUID, episodeID: String) {
        self = .subscription(subscriptionID, episodeID: episodeID)
    }

}
