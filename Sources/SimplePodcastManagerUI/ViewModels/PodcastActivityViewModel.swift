import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PodcastActivityViewModel {
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedState = false

    private let persistence: PodcastActivityPersistence
    private var state = PodcastActivityState()
    private var activityByPodcastID: [UUID: PodcastActivityEntry] = [:]

    public init(store: any PodcastActivityStateStore = SQLiteEpisodeStore.shared) {
        self.persistence = PodcastActivityPersistence(store: store)
    }

    public func load() async {
        do {
            state = try await persistence.load()
            rebuildIndex()
            lastErrorMessage = nil
            hasLoadedState = true
        } catch {
            state = PodcastActivityState()
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyPersistedState(_ state: PodcastActivityState) {
        self.state = state
        rebuildIndex()
        lastErrorMessage = nil
        hasLoadedState = true
    }

    public func updateAfterRefresh(
        subscriptions: [PodcastSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>
    ) async -> Int {
        let update = PodcastActivityPlanner.update(
            state,
            subscriptions: subscriptions,
            episodes: episodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs
        )
        state = update.state
        rebuildIndex()
        await persist()
        return update.discoveredEpisodeCount
    }

    public func acknowledge(_ episodes: [Episode]) async {
        guard !episodes.isEmpty else { return }
        state = PodcastActivityPlanner.acknowledging(episodes: episodes, in: state)
        rebuildIndex()
        await persist()
    }

    public func newEpisodeCount(for subscriptionID: UUID) -> Int {
        activityByPodcastID[subscriptionID]?.newEpisodeIDs.count ?? 0
    }

    public func newEpisodeIDs(for subscriptionID: UUID) -> Set<String> {
        activityByPodcastID[subscriptionID]?.newEpisodeIDs ?? []
    }

    public func newestPublicationDate(for subscriptionID: UUID) -> Date? {
        activityByPodcastID[subscriptionID]?.newestPublicationDate
    }

    public func isInactive(
        subscriptionID: UUID,
        threshold: InactivePodcastThreshold,
        currentDate: Date = Date()
    ) -> Bool {
        let activity = activityByPodcastID[subscriptionID]
        return PodcastActivityPlanner.isInactive(activity, threshold: threshold, currentDate: currentDate)
    }

    private func rebuildIndex() {
        activityByPodcastID = Dictionary(uniqueKeysWithValues: state.podcasts.map { ($0.subscriptionID, $0) })
    }

    private func persist() async {
        do {
            try await persistence.save(state)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

private actor PodcastActivityPersistence {
    let store: any PodcastActivityStateStore

    init(store: any PodcastActivityStateStore) {
        self.store = store
    }

    func load() throws -> PodcastActivityState { try store.loadPodcastActivityState() }
    func save(_ state: PodcastActivityState) throws { try store.savePodcastActivityState(state) }
}
