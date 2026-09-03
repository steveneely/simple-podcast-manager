import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastSearchViewModelTests {
    @Test
    func successfulSearchPublishesResultsAndNormalizesQuery() async throws {
        let recorder = PodcastSearchRecorder()
        let expectedResult = PodcastSearchResult(
            title: "Example Podcast",
            feedURL: URL(string: "https://example.com/feed.xml")!
        )
        let viewModel = PodcastSearchViewModel(
            searcher: RecordingPodcastSearcher(
                recorder: recorder,
                outcome: .success([expectedResult])
            )
        )
        viewModel.query = "  Example Podcast  "

        await viewModel.search()

        #expect(viewModel.results == [expectedResult])
        #expect(viewModel.hasSearched)
        #expect(!viewModel.isSearching)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(await recorder.queries == ["Example Podcast"])
    }

    @Test
    func shortQueryDoesNotStartASearch() async {
        let recorder = PodcastSearchRecorder()
        let viewModel = PodcastSearchViewModel(
            searcher: RecordingPodcastSearcher(
                recorder: recorder,
                outcome: .success([])
            )
        )
        viewModel.query = "x"

        await viewModel.search()

        #expect(!viewModel.canSearch)
        #expect(!viewModel.hasSearched)
        #expect(await recorder.queries.isEmpty)
    }

    @Test
    func failedSearchClearsResultsAndSurfacesReadableError() async {
        let viewModel = PodcastSearchViewModel(
            searcher: RecordingPodcastSearcher(
                recorder: PodcastSearchRecorder(),
                outcome: .failure(.unavailable)
            )
        )
        viewModel.query = "Example"

        await viewModel.search()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.hasSearched)
        #expect(!viewModel.isSearching)
        #expect(viewModel.lastErrorMessage == "Search is unavailable for this test.")
    }

    @Test
    func clearingResultsReturnsToTheInitialSearchState() async {
        let result = PodcastSearchResult(
            title: "Example Podcast",
            feedURL: URL(string: "https://example.com/feed.xml")!
        )
        let viewModel = PodcastSearchViewModel(
            searcher: RecordingPodcastSearcher(
                recorder: PodcastSearchRecorder(),
                outcome: .success([result])
            )
        )
        viewModel.query = "Example"
        await viewModel.search()

        viewModel.clearResults()

        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.hasSearched)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(!viewModel.isSearching)
    }
}

private struct RecordingPodcastSearcher: PodcastSearching {
    let recorder: PodcastSearchRecorder
    let outcome: Result<[PodcastSearchResult], PodcastSearchTestError>

    func searchPodcasts(matching query: String) async throws -> [PodcastSearchResult] {
        await recorder.record(query)
        return try outcome.get()
    }
}

private actor PodcastSearchRecorder {
    private(set) var queries: [String] = []

    func record(_ query: String) {
        queries.append(query)
    }
}

private enum PodcastSearchTestError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Search is unavailable for this test."
    }
}
