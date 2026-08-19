import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class AutomaticDownloadViewModel {
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedState: Bool

    private let store: any AutomaticDownloadStateStore
    private var state: AutomaticDownloadState

    public init(
        store: any AutomaticDownloadStateStore = JSONAutomaticDownloadStateStore(
            fileURL: JSONAutomaticDownloadStateStore.defaultFileURL()
        )
    ) {
        self.store = store
        self.state = AutomaticDownloadState()
        self.lastErrorMessage = nil
        self.hasLoadedState = false
    }

    public func load() {
        do {
            state = try store.loadState()
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
    ) -> [Episode] {
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
        persistState()
        return plan.episodesToDownload
    }

    public func applyPreferences(
        subscriptions: [FeedSubscription],
        limit: AutomaticDownloadLimit
    ) {
        state = AutomaticDownloadPlanner.applyingPreferences(
            to: state,
            subscriptions: subscriptions,
            limit: limit
        )
        persistState()
    }

    public func markDownloaded(_ episodes: [Episode]) {
        state = AutomaticDownloadPlanner.markingDownloaded(episodes, in: state)
        persistState()
    }

    private func persistState() {
        do {
            try store.saveState(state)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
