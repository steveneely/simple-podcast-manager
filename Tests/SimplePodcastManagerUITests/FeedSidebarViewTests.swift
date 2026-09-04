import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct FeedSidebarViewTests {
    @Test
    func appStartsWithoutSelectingAFeed() {
        #expect(FeedSelectionPolicy.initialSelection == nil)
    }

    @Test
    func clickingSelectedFeedClearsSelection() {
        let subscriptionID = UUID()

        let selection = FeedSidebarView.selection(
            afterClicking: subscriptionID,
            currentSelection: subscriptionID
        )

        #expect(selection == nil)
    }

    @Test
    func clickingDifferentFeedSelectsIt() {
        let selectedID = UUID()
        let clickedID = UUID()

        let selection = FeedSidebarView.selection(
            afterClicking: clickedID,
            currentSelection: selectedID
        )

        #expect(selection == clickedID)
    }

    @Test
    func newEpisodeStatusTakesPrecedenceOverInactiveStatus() {
        let status = FeedSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: true,
            hasFeedIssue: false,
            isEnabled: true
        )

        #expect(status == .newEpisodes(4))
    }

    @Test
    func refreshIssueAndDisabledFeedHideActivityStatus() {
        #expect(FeedSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: false,
            hasFeedIssue: true,
            isEnabled: true
        ) == nil)
        #expect(FeedSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: false,
            hasFeedIssue: false,
            isEnabled: false
        ) == nil)
    }

    @Test
    func inactiveStatusAppearsWithoutNewEpisodes() {
        let status = FeedSidebarView.activityStatus(
            newEpisodeCount: 0,
            isInactive: true,
            hasFeedIssue: false,
            isEnabled: true
        )

        #expect(status == .inactive)
    }

    @Test
    func newEpisodeLabelCapsLargeCounts() {
        #expect(FeedSidebarView.newEpisodeLabel(for: 4) == "4 new")
        #expect(FeedSidebarView.newEpisodeLabel(for: 100) == "99+ new")
    }

    @Test
    func alphabeticSortOrdersShowsByTitle() {
        let bravo = makeSubscription(title: "Bravo")
        let alpha = makeSubscription(title: "alpha")

        let sorted = FeedSidebarView.sortedSubscriptions(
            [bravo, alpha],
            by: .alphabetic,
            newestPublicationDate: { _ in nil }
        )

        #expect(sorted.map(\.id) == [alpha.id, bravo.id])
    }

    @Test
    func reverseAlphabeticSortOrdersShowsFromZToA() {
        let bravo = makeSubscription(title: "Bravo")
        let alpha = makeSubscription(title: "Alpha")

        let sorted = FeedSidebarView.sortedSubscriptions(
            [alpha, bravo],
            by: .reverseAlphabetic,
            newestPublicationDate: { _ in nil }
        )

        #expect(sorted.map(\.id) == [bravo.id, alpha.id])
    }

    @Test
    func recentlyUpdatedSortUsesNewestEpisodeThenTitleAndPlacesUndatedShowsLast() {
        let older = makeSubscription(title: "Older")
        let newestZulu = makeSubscription(title: "Zulu")
        let newestAlpha = makeSubscription(title: "Alpha")
        let undated = makeSubscription(title: "Undated")
        let dates = [
            older.id: Date(timeIntervalSince1970: 100),
            newestZulu.id: Date(timeIntervalSince1970: 200),
            newestAlpha.id: Date(timeIntervalSince1970: 200),
        ]

        let sorted = FeedSidebarView.sortedSubscriptions(
            [undated, newestZulu, older, newestAlpha],
            by: .recentlyUpdated,
            newestPublicationDate: { dates[$0.id] }
        )

        #expect(sorted.map(\.id) == [newestAlpha.id, newestZulu.id, older.id, undated.id])
    }

    @Test
    func leastRecentlyUpdatedSortPlacesUndatedAndOldestShowsFirst() {
        let older = makeSubscription(title: "Older")
        let newer = makeSubscription(title: "Newer")
        let undatedZulu = makeSubscription(title: "Zulu")
        let undatedAlpha = makeSubscription(title: "Alpha")
        let dates = [
            older.id: Date(timeIntervalSince1970: 100),
            newer.id: Date(timeIntervalSince1970: 200),
        ]

        let sorted = FeedSidebarView.sortedSubscriptions(
            [newer, undatedZulu, older, undatedAlpha],
            by: .leastRecentlyUpdated,
            newestPublicationDate: { dates[$0.id] }
        )

        #expect(sorted.map(\.id) == [undatedAlpha.id, undatedZulu.id, older.id, newer.id])
    }

    @Test
    func columnHeaderReversesTheCurrentSortDirection() {
        #expect(FeedSidebarView.reversedSortOrder(.alphabetic) == .reverseAlphabetic)
        #expect(FeedSidebarView.reversedSortOrder(.reverseAlphabetic) == .alphabetic)
        #expect(FeedSidebarView.reversedSortOrder(.recentlyUpdated) == .leastRecentlyUpdated)
        #expect(FeedSidebarView.reversedSortOrder(.leastRecentlyUpdated) == .recentlyUpdated)
    }

    @Test
    func choosingASortCriterionUsesItsNaturalDefaultDirection() {
        #expect(FeedSidebarView.defaultSortOrder(for: .name) == .alphabetic)
        #expect(FeedSidebarView.defaultSortOrder(for: .recentlyUpdated) == .recentlyUpdated)
        #expect(FeedSidebarView.sortCriterion(for: .reverseAlphabetic) == .name)
        #expect(FeedSidebarView.sortCriterion(for: .leastRecentlyUpdated) == .recentlyUpdated)
    }

    @Test
    func removingSelectedFeedDoesNotOpenAnotherFeed() {
        let selectedFeed = makeSubscription(title: "Selected")
        let remainingFeed = makeSubscription(title: "Remaining")

        let selection = FeedSelectionPolicy.selectionAfterRemovingFeeds(
            currentSelection: selectedFeed.id,
            remainingSubscriptions: [remainingFeed]
        )

        #expect(selection == nil)
    }

    @Test
    func removingAnotherFeedKeepsCurrentSelection() {
        let selectedFeed = makeSubscription(title: "Selected")

        let selection = FeedSelectionPolicy.selectionAfterRemovingFeeds(
            currentSelection: selectedFeed.id,
            remainingSubscriptions: [selectedFeed]
        )

        #expect(selection == selectedFeed.id)
    }

    private func makeSubscription(title: String) -> FeedSubscription {
        FeedSubscription(
            title: title,
            rssURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!
        )
    }
}
