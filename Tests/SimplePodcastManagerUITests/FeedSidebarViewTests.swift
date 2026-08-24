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
