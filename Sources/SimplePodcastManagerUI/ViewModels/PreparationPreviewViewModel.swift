import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PreparationPreviewViewModel {
    public private(set) var preparedEpisodes: [PreparedEpisode]
    public private(set) var downloadedEpisodes: [DownloadedEpisodeRecord]
    public private(set) var failures: [PreparationFailure]
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedPreparedEpisodes: Bool

    private let service: MediaPreparationService
    private let store: any PreparedEpisodeStore
    private let downloadedEpisodeStore: any DownloadedEpisodeStore
    private var preparingEpisodesByID: [EpisodePreparationID: Episode]

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
        self.lastErrorMessage = nil
        self.hasLoadedPreparedEpisodes = false
        self.preparingEpisodesByID = [:]
    }

    public var hasResults: Bool {
        !preparedEpisodes.isEmpty || !failures.isEmpty
    }

    public var isPreparing: Bool {
        !preparingEpisodesByID.isEmpty
    }

    public var preparingEpisodeCount: Int {
        preparingEpisodesByID.count
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
            recordDownloadedEpisodes(result.preparedEpisodes)
            persistPreparedEpisodes()
            persistDownloadedEpisodes()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func isPreparing(_ episode: Episode) -> Bool {
        preparingEpisodesByID[EpisodePreparationID(episode)] != nil
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
        let episodeID = EpisodePreparationID(episode)
        return preparedEpisodes.first(where: { EpisodePreparationID($0.episode) == episodeID })
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
        let episodeID = EpisodePreparationID(episode)
        preparedEpisodes.removeAll(where: { EpisodePreparationID($0.episode) == episodeID })
        failures.removeAll(where: { $0.episodeID == episode.id })
        persistPreparedEpisodes()
    }

    public func removeAllPreparedEpisodes() {
        for preparedEpisode in preparedEpisodes {
            removeFiles(for: preparedEpisode)
        }
        preparedEpisodes = []
        failures = []
        persistPreparedEpisodes()
    }

    private func merge(_ result: MediaPreparationResult) {
        var mergedPreparedEpisodes = Dictionary(
            uniqueKeysWithValues: preparedEpisodes.map { (EpisodePreparationID($0.episode), $0) }
        )
        for preparedEpisode in result.preparedEpisodes {
            mergedPreparedEpisodes[EpisodePreparationID(preparedEpisode.episode)] = preparedEpisode
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

    private func beginPreparing(_ episodes: [Episode]) {
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
}
