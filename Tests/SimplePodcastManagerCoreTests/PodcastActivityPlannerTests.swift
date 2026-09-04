import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct PodcastActivityPlannerTests {
    private let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test
    func firstRefreshEstablishesBaselineAndLaterRefreshCountsOnlyNewPrefix() {
        let subscription = makeSubscription()
        let baselineUpdate = PodcastActivityPlanner.update(
            PodcastActivityState(),
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        let baseline = baselineUpdate.state
        #expect(baselineUpdate.discoveredEpisodeCount == 0)
        #expect(baseline.podcasts[0].newEpisodeIDs.isEmpty)

        let refreshUpdate = PodcastActivityPlanner.update(
            baseline,
            subscriptions: [subscription],
            episodes: [episode("3", day: 3), episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        let updated = refreshUpdate.state
        #expect(refreshUpdate.discoveredEpisodeCount == 1)
        #expect(updated.podcasts[0].newEpisodeIDs == ["3"])
    }

    @Test
    func archiveExpansionDoesNotCountOldEpisodesAndMissingCurrentEpisodesLoseTheirBadge() {
        let subscription = makeSubscription()
        let initial = state(observed: ["3", "2"], new: ["3"], newestDay: 3)
        let expanded = PodcastActivityPlanner.updating(
            initial,
            subscriptions: [subscription],
            episodes: [episode("3", day: 3), episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        #expect(expanded.podcasts[0].newEpisodeIDs == ["3"])

        let disappeared = PodcastActivityPlanner.updating(
            expanded,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        #expect(disappeared.podcasts[0].newEpisodeIDs.isEmpty)
    }

    @Test
    func failedRefreshDoesNotAdvanceStateAndNextSuccessfulRefreshAccumulatesNewBadges() {
        let subscription = makeSubscription()
        let initial = state(observed: ["1"], newestDay: 1)
        let failed = PodcastActivityPlanner.updating(
            initial,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: [subscriptionID]
        )
        #expect(failed == initial)

        let openUpdate = PodcastActivityPlanner.update(
            initial,
            subscriptions: [subscription],
            episodes: [episode("2", day: 2), episode("1", day: 1)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        let open = openUpdate.state
        #expect(openUpdate.discoveredEpisodeCount == 1)
        #expect(open.podcasts[0].newEpisodeIDs == ["2"])
        #expect(open.podcasts[0].observedEpisodeIDs == ["2", "1"])
    }

    @Test
    func syncAndRSSURLChangeClearTheAppropriateNewState() {
        let initial = state(observed: ["3", "2"], new: ["3", "2"], newestDay: 3)
        let synced = PodcastActivityPlanner.acknowledging(episodes: [episode("3", day: 3)], in: initial)
        #expect(synced.podcasts[0].newEpisodeIDs == ["2"])
        let changedSubscription = PodcastSubscription(
            id: subscriptionID,
            title: "Show",
            rssURL: URL(string: "https://example.com/changed.xml")!
        )
        let reset = PodcastActivityPlanner.updating(
            initial,
            subscriptions: [changedSubscription],
            episodes: [episode("9", day: 9, feedURL: changedSubscription.rssURL)],
            refreshedSubscriptionIDs: [subscriptionID],
            failedSubscriptionIDs: []
        )
        #expect(reset.podcasts[0].newEpisodeIDs.isEmpty)
        #expect(reset.podcasts[0].observedEpisodeIDs == ["9"])
    }

    @Test
    func inactiveThresholdIsStrictAndOffOrMissingDatesNeverMarksInactive() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let current = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))!
        let cutoff = calendar.date(byAdding: .month, value: -6, to: current)!
        let exact = PodcastActivityEntry(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL, newestPublicationDate: cutoff)
        let old = PodcastActivityEntry(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL, newestPublicationDate: cutoff.addingTimeInterval(-1))
        let missing = PodcastActivityEntry(subscriptionID: subscriptionID, rssURL: makeSubscription().rssURL)

        #expect(!PodcastActivityPlanner.isInactive(exact, threshold: .sixMonths, currentDate: current, calendar: calendar))
        #expect(PodcastActivityPlanner.isInactive(old, threshold: .sixMonths, currentDate: current, calendar: calendar))
        #expect(!PodcastActivityPlanner.isInactive(old, threshold: .off, currentDate: current, calendar: calendar))
        #expect(!PodcastActivityPlanner.isInactive(missing, threshold: .sixMonths, currentDate: current, calendar: calendar))
    }

    @Test
    func inactiveCheckRepairsPersistedTwoDigitPublicationYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parsedAsYear26 = try #require(calendar.date(from: DateComponents(year: 26, month: 9, day: 1)))
        let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))
        let podcast = PodcastActivityEntry(
            subscriptionID: subscriptionID,
            rssURL: makeSubscription().rssURL,
            newestPublicationDate: parsedAsYear26
        )

        #expect(!PodcastActivityPlanner.isInactive(
            podcast,
            threshold: .sixMonths,
            currentDate: current,
            calendar: calendar
        ))
    }

    private func makeSubscription() -> PodcastSubscription {
        PodcastSubscription(id: subscriptionID, title: "Show", rssURL: URL(string: "https://example.com/feed.xml")!)
    }

    private func state(observed: [String], new: Set<String> = [], newestDay: Int) -> PodcastActivityState {
        PodcastActivityState(podcasts: [
            PodcastActivityEntry(
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
