import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastEditorViewTests {
    @Test
    func switchingAddMethodsRestoresEachMethodsURL() {
        let searchResult = PodcastSearchResult(
            title: "Search Result",
            feedURL: URL(string: "https://search.example.com/feed.xml")!
        )
        let manuallyEnteredURL = "https://manual.example.com/feed.xml"

        let searchURL = PodcastEditorView.activeRSSURLString(
            for: .search,
            selectedSearchResult: searchResult,
            rssFeedURLString: manuallyEnteredURL
        )
        let manualURL = PodcastEditorView.activeRSSURLString(
            for: .rssFeedURL,
            selectedSearchResult: searchResult,
            rssFeedURLString: manuallyEnteredURL
        )

        #expect(searchURL == searchResult.feedURL.absoluteString)
        #expect(manualURL == manuallyEnteredURL)
    }

    @Test
    func searchWithoutASelectionDoesNotReuseTheManualURL() {
        let searchURL = PodcastEditorView.activeRSSURLString(
            for: .search,
            selectedSearchResult: nil,
            rssFeedURLString: "https://manual.example.com/feed.xml"
        )

        #expect(searchURL.isEmpty)
    }
}
