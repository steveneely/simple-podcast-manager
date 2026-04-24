import Foundation
import Testing
@testable import SPodcastManagerCore
@testable import SPodcastManagerUI

@MainActor
struct RemovedEpisodeHistoryViewModelTests {
    @Test
    func recordDeletedEpisodesMarksMatchingEpisodeAsRemoved() {
        let subscriptionID = UUID(uuidString: "905B5061-7C79-4D27-8D70-331D714CE8DF")!
        let store = InMemoryRemovedEpisodeStore()
        let viewModel = RemovedEpisodeHistoryViewModel(store: store)
        let episode = Episode(
            id: "ep-1",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let deletedTargetURL = URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC/Example Podcast/2024.04.21-Episode 1-(Example Podcast).mp3")
        let removedAt = Date(timeIntervalSince1970: 1_713_800_000)

        viewModel.recordDeletedEpisodes(
            deletedTargetURLs: [deletedTargetURL],
            filesBySubscriptionID: [subscriptionID: [deletedTargetURL]],
            episodesBySubscriptionID: [subscriptionID: [episode]],
            removedAt: removedAt
        )

        #expect(viewModel.removedAt(for: episode) == removedAt)
        #expect(store.removedEpisodes.count == 1)
    }

    @Test
    func recordDeletedEpisodesIgnoresUnknownFiles() {
        let subscriptionID = UUID(uuidString: "905B5061-7C79-4D27-8D70-331D714CE8DF")!
        let store = InMemoryRemovedEpisodeStore()
        let viewModel = RemovedEpisodeHistoryViewModel(store: store)
        let episode = Episode(
            id: "ep-1",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        viewModel.recordDeletedEpisodes(
            deletedTargetURLs: [URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC/Example Podcast/Unknown.mp3")],
            filesBySubscriptionID: [subscriptionID: [URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC/Example Podcast/Unknown.mp3")]],
            episodesBySubscriptionID: [subscriptionID: [episode]],
            removedAt: Date(timeIntervalSince1970: 1_713_800_000)
        )

        #expect(viewModel.removedAt(for: episode) == nil)
        #expect(store.removedEpisodes.isEmpty)
    }
}

private final class InMemoryRemovedEpisodeStore: RemovedEpisodeStore, @unchecked Sendable {
    var removedEpisodes: [RemovedEpisodeRecord] = []

    func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord] {
        removedEpisodes
    }

    func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        self.removedEpisodes = removedEpisodes
    }
}
