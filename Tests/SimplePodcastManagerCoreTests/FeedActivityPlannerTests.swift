import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct FeedActivityPlannerTests {
    private let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test
    func firstRefreshEstablishesBaselineAndLaterRefreshCountsOnlyNewPrefix() {
        let subscription = makeSubscription()
        let baseline = FeedActivityPlanner.updating(
            FeedActivityState(),
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: nil
        )
        #expect(baseline.feeds[0].newEpisodeIDs.isEmpty)

        let updated = FeedActivityPlanner.updating(
            baseline,
            subscriptions: [subscription],
            episodes: [episode("3", day: 3), episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: nil
        )
        #expect(updated.feeds[0].newEpisodeIDs == ["3"])
    }

    @Test
    func archiveExpansionDoesNotCountOldEpisodesAndMissingCurrentEpisodesLoseTheirBadge() {
        let subscription = makeSubscription()
        let initial = state(observed: ["3", "2"], new: ["3"], newestDay: 3)
        let expanded = FeedActivityPlanner.updating(
            initial,
            subscriptions: [subscription],
            episodes: [episode("3", day: 3), episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: nil
        )
        #expect(expanded.feeds[0].newEpisodeIDs == ["3"])

        let disappeared = FeedActivityPlanner.updating(
            expanded,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: nil
        )
        #expect(disappeared.feeds[0].newEpisodeIDs.isEmpty)
    }

    @Test
    func failedRefreshDoesNotAdvanceStateAndOpenShowDoesNotAccumulateNewBadges() {
        let subscription = makeSubscription()
        let initial = state(observed: ["1"], newestDay: 1)
        let failed = FeedActivityPlanner.updating(
            initial,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [subscriptionID],
            openSubscriptionID: nil
        )
        #expect(failed == initial)

        let open = FeedActivityPlanner.updating(
            initial,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: subscriptionID
        )
        #expect(open.feeds[0].newEpisodeIDs.isEmpty)
        #expect(open.feeds[0].observedEpisodeIDs == ["2", "1"])
    }

    @Test
    func seenSyncAndFeedURLChangeClearTheAppropriateNewState() {
        let initial = state(observed: ["3", "2"], new: ["3", "2"], newestDay: 3)
        let synced = FeedActivityPlanner.acknowledging(episodes: [episode("3", day: 3)], in: initial)
        #expect(synced.feeds[0].newEpisodeIDs == ["2"])
        #expect(FeedActivityPlanner.markingSeen(subscriptionID: subscriptionID, in: synced).feeds[0].newEpisodeIDs.isEmpty)

        let changedSubscription = FeedSubscription(
            id: subscriptionID,
            title: "Show",
            rssURL: URL(string: "https://example.com/changed.xml")!
        )
        let reset = FeedActivityPlanner.updating(
            initial,
            subscriptions: [changedSubscription],
            episodes: [episode("9", day: 9, feedURL: changedSubscription.rssURL)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [],
            openSubscriptionID: nil
        )
        #expect(reset.feeds[0].newEpisodeIDs.isEmpty)
        #expect(reset.feeds[0].observedEpisodeIDs == ["9"])
    }

    @Test
    func inactiveThresholdIsStrictAndOffOrMissingDatesNeverMarksInactive() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let current = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))!
        let cutoff = calendar.date(byAdding: .month, value: -6, to: current)!
        let exact = FeedActivityFeedState(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL, newestPublicationDate: cutoff)
        let old = FeedActivityFeedState(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL, newestPublicationDate: cutoff.addingTimeInterval(-1))
        let missing = FeedActivityFeedState(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL)

        #expect(!FeedActivityPlanner.isInactive(exact, threshold: .sixMonths, currentDate: current, calendar: calendar))
        #expect(FeedActivityPlanner.isInactive(old, threshold: .sixMonths, currentDate: current, calendar: calendar))
        #expect(!FeedActivityPlanner.isInactive(old, threshold: .off, currentDate: current, calendar: calendar))
        #expect(!FeedActivityPlanner.isInactive(missing, threshold: .sixMonths, currentDate: current, calendar: calendar))
    }

    @Test
    func inactiveCheckRepairsPersistedTwoDigitPublicationYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parsedAsYear26 = try #require(calendar.date(from: DateComponents(year: 26, month: 9, day: 1)))
        let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))
        let feed = FeedActivityFeedState(
            subscriptionID: subscriptionID,
            rssURL: makeSubscription().rssURL,
            newestPublicationDate: parsedAsYear26
        )

        #expect(!FeedActivityPlanner.isInactive(
            feed,
            threshold: .sixMonths,
            currentDate: current,
            calendar: calendar
        ))
    }

    private func makeSubscription() -> FeedSubscription {
        FeedSubscription(id: subscriptionID, title: "Show", rssURL: URL(string: "https://example.com/feed.xml")!)
    }

    private func state(observed: [String], new: Set<String> = [], newestDay: Int) -> FeedActivityState {
        FeedActivityState(feeds: [
            FeedActivityFeedState(
                subscriptionID: subscriptionID,
                rssURL: makeSubscription().rssURL,
                observedEpisodeIDs: observed,
                newEpisodeIDs: new,
                newestPublicationDate: date(day: newestDay)
            )
        ])
    }

    private func episode(_ id: String, day: Int, feedURL: URL? = nil) -> Episode {
        Episode(
            id: id,
            subscriptionID: subscriptionID,
            podcastTitle: "Show",
            title: "Episode \(id)",
            publicationDate: date(day: day),
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: feedURL ?? makeSubscription().rssURL
        )
    }

    private func date(day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day * 86_400)) }
}
