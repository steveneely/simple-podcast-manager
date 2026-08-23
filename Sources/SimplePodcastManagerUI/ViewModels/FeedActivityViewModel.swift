import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class FeedActivityViewModel {
    public private(set) var lastErrorMessage: String?
    public private(set) var hasLoadedState = false

    private let persistence: FeedActivityPersistence
    private var state = FeedActivityState()
    private var feedsBySubscriptionID: [UUID: FeedActivityFeedState] = [:]

    public init(store: any FeedActivityStateStore = SQLiteEpisodeStore.shared) {
        self.persistence = FeedActivityPersistence(store: store)
    }

    public func load() async {
        do {
            state = try await persistence.load()
            rebuildIndex()
            lastErrorMessage = nil
            hasLoadedState = true
        } catch {
            state = FeedActivityState()
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyPersistedState(_ state: FeedActivityState) {
        self.state = state
        rebuildIndex()
        lastErrorMessage = nil
        hasLoadedState = true
    }

    public func updateAfterRefresh(
        subscriptions: [FeedSubscription],
        episodes: [Episode],
        refreshedSubscriptionIDs: Set<UUID>,
        failedSubscriptionIDs: Set<UUID>,
        openSubscriptionID: UUID?
    ) async {
        state = FeedActivityPlanner.updating(
            state,
            subscriptions: subscriptions,
            episodes: episodes,
            refreshedSubscriptionIDs: refreshedSubscriptionIDs,
            failedSubscriptionIDs: failedSubscriptionIDs,
            openSubscriptionID: openSubscriptionID
        )
        rebuildIndex()
        await persist()
    }

    public func markSeen(subscriptionID: UUID) async {
        state = FeedActivityPlanner.markingSeen(subscriptionID: subscriptionID, in: state)
        rebuildIndex()
        await persist()
    }

    public func acknowledgeSynced(_ episodes: [Episode]) async {
        state = FeedActivityPlanner.acknowledging(episodes: episodes, in: state)
        rebuildIndex()
        await persist()
    }

    public func newEpisodeCount(for subscriptionID: UUID) -> Int {
        feedsBySubscriptionID[subscriptionID]?.newEpisodeIDs.count ?? 0
    }

    public func newestPublicationDate(for subscriptionID: UUID) -> Date? {
        feedsBySubscriptionID[subscriptionID]?.newestPublicationDate
    }

    public func isInactive(
        subscriptionID: UUID,
        threshold: InactivePodcastThreshold,
        currentDate: Date = Date()
    ) -> Bool {
        let feed = feedsBySubscriptionID[subscriptionID]
        return FeedActivityPlanner.isInactive(feed, threshold: threshold, currentDate: currentDate)
    }

    private func rebuildIndex() {
        feedsBySubscriptionID = Dictionary(uniqueKeysWithValues: state.feeds.map { ($0.subscriptionID, $0) })
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

private actor FeedActivityPersistence {
    let store: any FeedActivityStateStore

    init(store: any FeedActivityStateStore) {
        self.store = store
    }

    func load() throws -> FeedActivityState { try store.loadFeedActivityState() }
    func save(_ state: FeedActivityState) throws { try store.saveFeedActivityState(state) }
}
