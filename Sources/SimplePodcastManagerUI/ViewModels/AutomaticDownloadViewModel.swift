import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class AutomaticDownloadViewModel {
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedState: Bool

    private let persistence: AutomaticDownloadStatePersistence
    private var state: AutomaticDownloadState

    public init(
        store: any AutomaticDownloadStateStore = SQLiteEpisodeStore.shared
    ) {
        self.persistence = AutomaticDownloadStatePersistence(store: store)
        self.state = AutomaticDownloadState()
        self.lastErrorMessage = nil
        self.hasLoadedState = false
    }

    public func load() async {
        do {
            state = try await persistence.load()
            lastErrorMessage = nil
            hasLoadedState = true
        } catch {
            state = AutomaticDownloadState()
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func episodesToDownload(
        afterRefreshing refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        downloadedEpisodeIDs: Set<AutomaticDownloadEpisodeID>,
        limit: AutomaticDownloadLimit
    ) async -> [Episode] {
        let plan = AutomaticDownloadPlanner.makePlan(
            state: state,
            subscriptions: subscriptions,
            episodes: episodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            downloadedEpisodeIDs: downloadedEpisodeIDs,
            limit: limit
        )
        state = plan.state
        await persistState()
        return plan.episodesToDownload
    }

    public func applyPreferences(
        subscriptions: [FeedSubscription],
        limit: AutomaticDownloadLimit
    ) async {
        state = AutomaticDownloadPlanner.applyingPreferences(
            to: state,
            subscriptions: subscriptions,
            limit: limit
        )
        await persistState()
    }

    public func markDownloaded(_ episodes: [Episode]) async {
        state = AutomaticDownloadPlanner.markingDownloaded(episodes, in: state)
        await persistState()
    }

    private func persistState() async {
        do {
            try await persistence.save(state)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private actor AutomaticDownloadStatePersistence {
    private let store: any AutomaticDownloadStateStore

    init(store: any AutomaticDownloadStateStore) {
        self.store = store
    }

    func load() throws -> AutomaticDownloadState {
        try store.loadState()
    }

    func save(_ state: AutomaticDownloadState) throws {
        try store.saveState(state)
    }
}
