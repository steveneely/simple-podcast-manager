import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct AutomaticDownloadPlannerTests {
    @Test
    func firstRefreshEstablishesBaselineWithoutDownloadingBacklog() {
        let subscription = makeSubscription()
        let episodes = [
            makeEpisode("older", subscription: subscription, day: 1),
            makeEpisode("newer", subscription: subscription, day: 2),
        ]

        let plan = makePlan(
            state: AutomaticDownloadState(),
            subscription: subscription,
            episodes: episodes,
            limit: .allNew
        )

        #expect(plan.episodesToDownload.isEmpty)
        #expect(plan.state.feeds.first?.observedEpisodeIDs == ["newer", "older"])
    }

    @Test(arguments: [
        (AutomaticDownloadLimit.latest1, 1),
        (.latest2, 2),
        (.latest3, 3),
        (.allNew, 4),
    ])
    func limitSelectsNewestEpisodesPerFeed(limit: AutomaticDownloadLimit, expectedCount: Int) {
        let subscription = makeSubscription()
        let baseline = makeEpisode("baseline", subscription: subscription, day: 1)
        let initialState = baselineState(subscription: subscription, episodeIDs: [baseline.id])
        let newEpisodes = (2...5).map { makeEpisode("new-\($0)", subscription: subscription, day: $0) }

        let plan = makePlan(
            state: initialState,
            subscription: subscription,
            episodes: [baseline] + newEpisodes,
            limit: limit
        )

        #expect(plan.episodesToDownload.map(\.id) == Array(["new-5", "new-4", "new-3", "new-2"].prefix(expectedCount)))
    }

    @Test
    func numericLimitAppliesToEachFeed() {
        let first = makeSubscription()
        let second = makeSubscription()
        let state = AutomaticDownloadState(feeds: [
            AutomaticDownloadFeedState(
                subscriptionID: first.id,
                rssURL: first.rssURL,
                observedEpisodeIDs: ["first-baseline"]
            ),
            AutomaticDownloadFeedState(
                subscriptionID: second.id,
                rssURL: second.rssURL,
                observedEpisodeIDs: ["second-baseline"]
            ),
        ])
        let episodes = [
            makeEpisode("first-baseline", subscription: first, day: 1),
            makeEpisode("first-new", subscription: first, day: 2),
            makeEpisode("second-baseline", subscription: second, day: 1),
            makeEpisode("second-new", subscription: second, day: 2),
        ]

        let plan = AutomaticDownloadPlanner.makePlan(
            state: state,
            subscriptions: [first, second],
            episodes: episodes,
            refreshedSubscriptionIDs: [first.id, second.id],
            failedSubscriptionIDs: [],
            downloadedEpisodeIDs: [],
            limit: .latest1
        )

        #expect(Set(plan.episodesToDownload.map(\.id)) == ["first-new", "second-new"])
    }

    @Test
    func episodesSkippedByLimitDoNotTrickleIntoLaterRefreshes() {
        let subscription = makeSubscription()
        let baseline = makeEpisode("baseline", subscription: subscription, day: 1)
        let firstPlan = makePlan(
            state: baselineState(subscription: subscription, episodeIDs: [baseline.id]),
            subscription: subscription,
            episodes: [
                baseline,
                makeEpisode("newer", subscription: subscription, day: 3),
                makeEpisode("skipped", subscription: subscription, day: 2),
            ],
            limit: .latest1
        )

        let secondPlan = makePlan(
            state: AutomaticDownloadPlanner.markingDownloaded(firstPlan.episodesToDownload, in: firstPlan.state),
            subscription: subscription,
            episodes: [
                baseline,
                makeEpisode("newer", subscription: subscription, day: 3),
                makeEpisode("skipped", subscription: subscription, day: 2),
            ],
            limit: .latest1
        )

        #expect(firstPlan.episodesToDownload.map(\.id) == ["newer"])
        #expect(secondPlan.episodesToDownload.isEmpty)
    }

    @Test
    func offAndExcludedFeedsAdvanceBaselineWithoutDownloading() {
        var excludedSubscription = makeSubscription()
        excludedSubscription.includesInAutomaticDownloads = false
        let baseline = makeEpisode("baseline", subscription: excludedSubscription, day: 1)
        let newEpisode = makeEpisode("observed", subscription: excludedSubscription, day: 2)

        let excludedPlan = makePlan(
            state: baselineState(subscription: excludedSubscription, episodeIDs: [baseline.id]),
            subscription: excludedSubscription,
            episodes: [baseline, newEpisode],
            limit: .allNew
        )
        var includedSubscription = excludedSubscription
        includedSubscription.includesInAutomaticDownloads = true
        let laterPlan = makePlan(
            state: excludedPlan.state,
            subscription: includedSubscription,
            episodes: [baseline, newEpisode],
            limit: .allNew
        )

        #expect(excludedPlan.episodesToDownload.isEmpty)
        #expect(laterPlan.episodesToDownload.isEmpty)
    }

    @Test
    func enablingDownloadsQueuesOnlyCurrentlyNewUndownloadedEpisodesWithinLimit() {
        let subscription = makeSubscription()
        let olderEpisode = makeEpisode("older", subscription: subscription, day: 1)
        let secondNewEpisode = makeEpisode("second-new", subscription: subscription, day: 2)
        let newestEpisode = makeEpisode("newest", subscription: subscription, day: 3)
        let state = baselineState(
            subscription: subscription,
            episodeIDs: [newestEpisode.id, secondNewEpisode.id, olderEpisode.id]
        )

        let plan = AutomaticDownloadPlanner.activatingCurrentlyNewEpisodes(
            in: state,
            subscriptionIDs: [subscription.id],
            subscriptions: [subscription],
            episodes: [olderEpisode, secondNewEpisode, newestEpisode],
            newEpisodeIDsBySubscription: [
                subscription.id: [newestEpisode.id, secondNewEpisode.id],
            ],
            downloadedEpisodeIDs: [AutomaticDownloadEpisodeID(newestEpisode)!],
            limit: .latest1
        )

        #expect(plan.episodesToDownload == [secondNewEpisode])
        #expect(plan.state.feeds.first?.pendingEpisodeIDs == [secondNewEpisode.id])
    }

    @Test
    func enablingDownloadsDoesNotQueueNewEpisodesForAnExcludedShow() {
        var subscription = makeSubscription()
        subscription.includesInAutomaticDownloads = false
        let newEpisode = makeEpisode("new", subscription: subscription, day: 2)

        let plan = AutomaticDownloadPlanner.activatingCurrentlyNewEpisodes(
            in: baselineState(subscription: subscription, episodeIDs: [newEpisode.id]),
            subscriptionIDs: [subscription.id],
            subscriptions: [subscription],
            episodes: [newEpisode],
            newEpisodeIDsBySubscription: [subscription.id: [newEpisode.id]],
            downloadedEpisodeIDs: [],
            limit: .allNew
        )

        #expect(plan.episodesToDownload.isEmpty)
        #expect(plan.state.feeds.first?.pendingEpisodeIDs.isEmpty == true)
    }

    @Test
    func failedRefreshPreservesPendingEpisodes() {
        let subscription = makeSubscription()
        let pending = makeEpisode("pending", subscription: subscription, day: 2)
        let state = AutomaticDownloadState(feeds: [
            AutomaticDownloadFeedState(
                subscriptionID: subscription.id,
                rssURL: subscription.rssURL,
                observedEpisodeIDs: ["baseline", pending.id],
                pendingEpisodeIDs: [pending.id]
            )
        ])

        let plan = AutomaticDownloadPlanner.makePlan(
            state: state,
            subscriptions: [subscription],
            episodes: [pending],
            refreshedSubscriptionIDs: [subscription.id],
            failedSubscriptionIDs: [subscription.id],
            downloadedEpisodeIDs: [],
            limit: .allNew
        )

        #expect(plan.episodesToDownload.isEmpty)
        #expect(plan.state == state)
    }

    @Test
    func pendingEpisodeRetriesUntilDownloadedAndHistoryPreventsRedownload() {
        let subscription = makeSubscription()
        let pending = makeEpisode("pending", subscription: subscription, day: 2)
        let state = AutomaticDownloadState(feeds: [
            AutomaticDownloadFeedState(
                subscriptionID: subscription.id,
                rssURL: subscription.rssURL,
                observedEpisodeIDs: [pending.id],
                pendingEpisodeIDs: [pending.id]
            )
        ])

        let retryPlan = makePlan(
            state: state,
            subscription: subscription,
            episodes: [pending],
            limit: .allNew
        )
        let downloadedPlan = AutomaticDownloadPlanner.makePlan(
            state: retryPlan.state,
            subscriptions: [subscription],
            episodes: [pending],
            refreshedSubscriptionIDs: [subscription.id],
            failedSubscriptionIDs: [],
            downloadedEpisodeIDs: [AutomaticDownloadEpisodeID(pending)!],
            limit: .allNew
        )

        #expect(retryPlan.episodesToDownload == [pending])
        #expect(downloadedPlan.episodesToDownload.isEmpty)
        #expect(downloadedPlan.state.feeds.first?.pendingEpisodeIDs.isEmpty == true)
    }

    @Test
    func feedURLChangeAndReenabledFeedEstablishNewBaselines() {
        var subscription = makeSubscription()
        let oldState = baselineState(subscription: subscription, episodeIDs: ["old"])
        subscription.rssURL = URL(string: "https://example.com/replacement.xml")!
        let replacementEpisode = makeEpisode("replacement", subscription: subscription, day: 2)

        let changedURLPlan = makePlan(
            state: oldState,
            subscription: subscription,
            episodes: [replacementEpisode],
            limit: .allNew
        )
        var disabledSubscription = subscription
        disabledSubscription.isEnabled = false
        let disabledState = AutomaticDownloadPlanner.applyingPreferences(
            to: changedURLPlan.state,
            subscriptions: [disabledSubscription],
            limit: .allNew
        )
        let reenabledPlan = makePlan(
            state: disabledState,
            subscription: subscription,
            episodes: [replacementEpisode],
            limit: .allNew
        )

        #expect(changedURLPlan.episodesToDownload.isEmpty)
        #expect(disabledState.feeds.isEmpty)
        #expect(reenabledPlan.episodesToDownload.isEmpty)
    }

    private func makePlan(
        state: AutomaticDownloadState,
        subscription: FeedSubscription,
        episodes: [Episode],
        limit: AutomaticDownloadLimit
    ) -> AutomaticDownloadPlan {
        AutomaticDownloadPlanner.makePlan(
            state: state,
            subscriptions: [subscription],
            episodes: episodes,
            refreshedSubscriptionIDs: [subscription.id],
            failedSubscriptionIDs: [],
            downloadedEpisodeIDs: [],
            limit: limit
        )
    }

    private func baselineState(
        subscription: FeedSubscription,
        episodeIDs: [String]
    ) -> AutomaticDownloadState {
        AutomaticDownloadState(feeds: [
            AutomaticDownloadFeedState(
                subscriptionID: subscription.id,
                rssURL: subscription.rssURL,
                observedEpisodeIDs: episodeIDs
            )
        ])
    }

    private func makeSubscription() -> FeedSubscription {
        FeedSubscription(
            id: UUID(),
            title: "Example",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
    }

    private func makeEpisode(_ id: String, subscription: FeedSubscription, day: Int) -> Episode {
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
