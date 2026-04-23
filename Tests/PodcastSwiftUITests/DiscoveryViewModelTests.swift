import Foundation
import Testing
@testable import PodcastSwiftCore
@testable import PodcastSwiftUI

@MainActor
struct DiscoveryViewModelTests {
    @Test
    func searchLoadsResultsFromService() async throws {
        let service = MockPodcastDiscoveryService(results: [
            DiscoveryResult(
                id: "atp",
                title: "Accidental Tech Podcast",
                author: "ATP",
                summary: "Three nerds talking tech.",
                feedURL: URL(string: "https://atp.fm/rss"),
                source: "Mock"
            )
        ])
        let viewModel = DiscoveryViewModel(
            searchText: "atp",
            serviceFactory: { _ in service }
        )

        await viewModel.search(using: AppSettings())

        #expect(viewModel.results.count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func missingCredentialsLeavesManualEntryAvailable() async throws {
        let viewModel = DiscoveryViewModel(searchText: "atp")

        await viewModel.search(using: AppSettings())

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.errorMessage == PodcastDiscoveryError.missingCredentials.localizedDescription)
    }
}

private struct MockPodcastDiscoveryService: PodcastDiscoveryService {
    let results: [DiscoveryResult]

    func searchPodcasts(matching query: String) async throws -> [DiscoveryResult] {
        results
    }
}
