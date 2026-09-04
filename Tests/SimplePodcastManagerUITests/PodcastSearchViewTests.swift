import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastSearchViewTests {
    @Test
    func clickingSelectedResultClearsSelection() {
        let result = makeResult(title: "Selected", path: "selected.xml")

        let selection = PodcastSearchView.selection(
            afterClicking: result,
            currentSelection: result
        )

        #expect(selection == nil)
    }

    @Test
    func clickingDifferentResultSelectsIt() {
        let selectedResult = makeResult(title: "Selected", path: "selected.xml")
        let clickedResult = makeResult(title: "Clicked", path: "clicked.xml")

        let selection = PodcastSearchView.selection(
            afterClicking: clickedResult,
            currentSelection: selectedResult
        )

        #expect(selection == clickedResult)
    }

    private func makeResult(title: String, path: String) -> PodcastSearchResult {
        PodcastSearchResult(
            title: title,
            feedURL: URL(string: "https://example.com/\(path)")!
        )
    }
}
