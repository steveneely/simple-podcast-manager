import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct AutomaticDownloadViewModelTests {
    @Test
    func persistsBaselinePendingAndDownloadedState() async throws {
        let store = InMemoryAutomaticDownloadStateStore()
        let viewModel = AutomaticDownloadViewModel(store: store)
        let subscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let baselineEpisode = makeEpisode("baseline", day: 1, subscription: subscription)
        let newEpisode = makeEpisode("new", day: 2, subscription: subscription)

        await viewModel.load()
        let baselineDownloads = await viewModel.episodesToDownload(
            afterRefreshing: [subscription.id],
            failedSubscriptionIDs: [],
            subscriptions: [subscription],
            episodes: [baselineEpisode],
            downloadedEpisodeIDs: [],
            limit: .latest1
        )
        let newDownloads = await viewModel.episodesToDownload(
            afterRefreshing: [subscription.id],
            failedSubscriptionIDs: [],
            subscriptions: [subscription],
            episodes: [baselineEpisode, newEpisode],
            downloadedEpisodeIDs: [],
            limit: .latest1
        )

        #expect(baselineDownloads.isEmpty)
        #expect(newDownloads == [newEpisode])
        #expect(try store.loadState().feeds.first?.pendingEpisodeIDs == [newEpisode.id])

        await viewModel.markDownloaded([newEpisode])
        #expect(try store.loadState().feeds.first?.pendingEpisodeIDs.isEmpty == true)
    }

    @Test
    func applyingOffPreferenceClearsPendingWork() async throws {
        let subscription = FeedSubscription(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let store = InMemoryAutomaticDownloadStateStore(
            state: AutomaticDownloadState(feeds: [
                AutomaticDownloadFeedState(
                    subscriptionID: subscription.id,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: ["episode"],
                    pendingEpisodeIDs: ["episode"]
                )
            ])
        )
        let viewModel = AutomaticDownloadViewModel(store: store)

        await viewModel.load()
        await viewModel.applyPreferences(subscriptions: [subscription], limit: .off)

        #expect(try store.loadState().feeds.first?.pendingEpisodeIDs.isEmpty == true)
    }

    @Test
    func activatingDownloadsPersistsCurrentlyNewEpisodesAsPending() async throws {
        let subscription = FeedSubscription(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let newEpisode = makeEpisode("new", day: 2, subscription: subscription)
        let store = InMemoryAutomaticDownloadStateStore(
            state: AutomaticDownloadState(feeds: [
                AutomaticDownloadFeedState(
                    subscriptionID: subscription.id,
                    rssURL: subscription.rssURL,
                    observedEpisodeIDs: [newEpisode.id]
                )
            ])
        )
        let viewModel = AutomaticDownloadViewModel(store: store)
        await viewModel.load()

        let episodes = await viewModel.activateDownloadsForCurrentlyNewEpisodes(
            subscriptionIDs: [subscription.id],
            subscriptions: [subscription],
            episodes: [newEpisode],
            newEpisodeIDsBySubscription: [subscription.id: [newEpisode.id]],
            downloadedEpisodeIDs: [],
            limit: .latest1
        )

        #expect(episodes == [newEpisode])
        #expect(try store.loadState().feeds.first?.pendingEpisodeIDs == [newEpisode.id])
    }

    private func makeEpisode(_ id: String, day: Int, subscription: FeedSubscription) -> Episode {
        Episode(
            id: id,
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: id,
            publicationDate: Date(timeIntervalSince1970: TimeInterval(day * 86_400)),
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: subscription.rssURL
        )
    }
}

private final class InMemoryAutomaticDownloadStateStore: AutomaticDownloadStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: AutomaticDownloadState

    init(state: AutomaticDownloadState = AutomaticDownloadState()) {
        self.state = state
    }

    func loadState() throws -> AutomaticDownloadState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func saveState(_ state: AutomaticDownloadState) throws {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
    }
}
