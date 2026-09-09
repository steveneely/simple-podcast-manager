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
    private var preparationTasksByID: [EpisodePreparationID: Task<Void, Never>]
    private var pendingPreparationIDs: [EpisodePreparationID] = []
    private var preparationJobs: [EpisodePreparationID: PreparationJob] = [:]
    private let maximumConcurrentPreparations = 3

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
        self.preparationTasksByID = [:]
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
        var seen: Set<EpisodePreparationID> = []
        let requestedEpisodes = episodes.filter {
            preparedEpisode(for: $0) == nil && seen.insert(EpisodePreparationID($0)).inserted
        }
        guard !requestedEpisodes.isEmpty else { return }
        lastErrorMessage = nil
        beginPreparing(requestedEpisodes.filter { preparationJobs[EpisodePreparationID($0)] == nil })

        await withCheckedContinuation { continuation in
            var remaining = requestedEpisodes.count
            let completed: @MainActor () -> Void = {
                remaining -= 1
                if remaining == 0 { continuation.resume() }
            }
            for episode in requestedEpisodes {
                let id = EpisodePreparationID(episode)
                if preparationJobs[id] != nil {
                    preparationJobs[id]?.completions.append(completed)
                } else {
                    preparationJobs[id] = PreparationJob(episode: episode, settings: settings, completions: [completed])
                    pendingPreparationIDs.append(id)
                }
            }
            startPendingPreparations()
        }
    }

    private func startPendingPreparations() {
        while preparationTasksByID.count < maximumConcurrentPreparations, !pendingPreparationIDs.isEmpty {
            let id = pendingPreparationIDs.removeFirst()
            guard let job = preparationJobs[id] else { continue }
            let service = self.service
            preparationTasksByID[id] = Task {
                let result = await service.prepareEpisode(job.episode, settings: job.settings)
                if Task.isCancelled, case .prepared(let prepared) = result {
                    // Cancellation can arrive while the completed result hops back to the UI actor.
                    do { try await removeFiles(for: prepared) }
                    catch { lastErrorMessage = deletionErrorMessage(for: prepared, error: error) }
                } else {
                    applyPreparationResult(result)
                }
                finishPreparation(id)
            }
        }
    }

    private func applyPreparationResult(_ result: MediaPreparationResult) {
        switch result {
        case .prepared(let prepared):
            preparedEpisodes.removeAll { EpisodePreparationID($0.episode) == EpisodePreparationID(prepared.episode) }
            preparedEpisodes.append(prepared)
            preparedEpisodes.sort { $0.episode.title.localizedCaseInsensitiveCompare($1.episode.title) == .orderedAscending }
            let downloadedRecords = recordDownloadedEpisodes([prepared])
            persistNewPreparedEpisodes([prepared])
            persistNewDownloadedEpisodes(downloadedRecords)
        case .failed(let failure):
            mergeFailures([failure])
        case .cancelled:
            break
        }
    }

    private func finishPreparation(_ id: EpisodePreparationID) {
        preparationTasksByID.removeValue(forKey: id)
        preparingEpisodesByID.removeValue(forKey: id)
        let completions = preparationJobs.removeValue(forKey: id)?.completions ?? []
        startPendingPreparations()
        for completed in completions { completed() }
    }

    public func cancelPreparation(for episode: Episode) {
        let id = EpisodePreparationID(episode)
        if let task = preparationTasksByID[id] {
            task.cancel()
        } else if preparationJobs[id] != nil {
            pendingPreparationIDs.removeAll { $0 == id }
            finishPreparation(id)
        }
    }

    public func isPreparing(_ episode: Episode) -> Bool {
        preparingEpisodesByID[EpisodePreparationID(episode)] != nil
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

    public func removePreparedEpisodes(_ candidates: [PreparedEpisode]) async {
        var removedEpisodeIDs: Set<EpisodePreparationID> = []
        var deletionErrors: [String] = []

        for preparedEpisode in candidates {
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

    public func removeDownloads(forSubscriptionIDs subscriptionIDs: Set<UUID>) async -> Bool {
        guard !subscriptionIDs.isEmpty else { return true }
        guard !preparingEpisodesByID.values.contains(where: { episode in
            episode.subscriptionID.map(subscriptionIDs.contains) == true
        }) else {
            lastErrorMessage = "Wait for this podcast's active downloads to finish, then try deleting it again."
            return false
        }

        let matchingPreparedEpisodes = preparedEpisodes.filter { preparedEpisode in
            preparedEpisode.episode.subscriptionID.map(subscriptionIDs.contains) == true
        }
        var removedEpisodeIDs: Set<EpisodePreparationID> = []
        var deletionErrors: [String] = []

        for preparedEpisode in matchingPreparedEpisodes {
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

        guard deletionErrors.isEmpty else {
            lastErrorMessage = deletionErrors.joined(separator: "\n")
            return false
        }

        let remainingDownloadedEpisodes = downloadedEpisodes.filter {
            !subscriptionIDs.contains($0.subscriptionID)
        }
        let downloadedEpisodeStore = self.downloadedEpisodeStore
        do {
            try await Task.detached(priority: .userInitiated) {
                try downloadedEpisodeStore.saveDownloadedEpisodes(remainingDownloadedEpisodes)
            }.value
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }

        downloadedEpisodes = remainingDownloadedEpisodes
        failures.removeAll { failure in
            failure.episode.subscriptionID.map(subscriptionIDs.contains) == true
        }
        rebuildIndexes()
        lastErrorMessage = nil
        return true
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
    case rssFeed(URL, episodeID: String)

    init(_ episode: Episode) {
        if let subscriptionID = episode.subscriptionID {
            self = .subscription(subscriptionID, episodeID: episode.id)
        } else {
            self = .rssFeed(episode.sourceFeedURL, episodeID: episode.id)
        }
    }

    init(subscriptionID: UUID, episodeID: String) {
        self = .subscription(subscriptionID, episodeID: episodeID)
    }

}

private struct PreparationJob {
    let episode: Episode
    let settings: AppSettings
    var completions: [@MainActor () -> Void]
}
