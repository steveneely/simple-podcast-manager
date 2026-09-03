import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class PodcastSearchViewModel {
    public var query = ""
    public private(set) var results: [PodcastSearchResult] = []
    public private(set) var isSearching = false
    public private(set) var lastErrorMessage: String?
    public private(set) var hasSearched = false

    private let searcher: any PodcastSearching
    private var activeSearchID: UUID?

    public init(searcher: any PodcastSearching = PodcastIndexSearchService()) {
        self.searcher = searcher
    }

    public var canSearch: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isSearching
    }

    public func search() async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else { return }

        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        lastErrorMessage = nil

        do {
            let searchResults = try await searcher.searchPodcasts(matching: normalizedQuery)
            guard activeSearchID == searchID else { return }
            results = searchResults
            hasSearched = true
            isSearching = false
        } catch is CancellationError {
            guard activeSearchID == searchID else { return }
            isSearching = false
        } catch {
            guard activeSearchID == searchID else { return }
            results = []
            hasSearched = true
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isSearching = false
        }
    }

    public func cancelSearch() {
        activeSearchID = nil
        isSearching = false
    }

    public func clearResults() {
        cancelSearch()
        results = []
        lastErrorMessage = nil
        hasSearched = false
    }
}
