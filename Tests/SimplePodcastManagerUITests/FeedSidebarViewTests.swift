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
