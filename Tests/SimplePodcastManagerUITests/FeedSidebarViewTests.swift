import Foundation
import Testing
@testable import SimplePodcastManagerUI

@MainActor
struct FeedSidebarViewTests {
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
}
