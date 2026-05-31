import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

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
            deviceName: "WALKMAN",
            removedAt: removedAt
        )

        #expect(viewModel.removedAt(for: episode) == removedAt)
        #expect(store.removedEpisodes.count == 1)
        #expect(viewModel.removedRecord(for: episode)?.deviceName == "WALKMAN")
    }

    @Test
    func recordDeletedEpisodesPersistsHistoryWithoutCurrentEpisodeMatch() {
        let subscriptionID = UUID(uuidString: "905B5061-7C79-4D27-8D70-331D714CE8DF")!
        let store = InMemoryRemovedEpisodeStore()
        let viewModel = RemovedEpisodeHistoryViewModel(store: store)
        let deletedTargetURL = URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC/Example Podcast/2024.04.21-Episode 1-(Example Podcast).mp3")
        let removedAt = Date(timeIntervalSince1970: 1_713_800_000)
        let laterLoadedEpisode = Episode(
            id: "different-feed-id",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        viewModel.recordDeletedEpisodes(
            deletedTargetURLs: [deletedTargetURL],
            filesBySubscriptionID: [subscriptionID: [deletedTargetURL]],
            episodesBySubscriptionID: [subscriptionID: []],
            deviceName: "WALKMAN",
            removedAt: removedAt
        )

        #expect(store.removedEpisodes.count == 1)
        #expect(store.removedEpisodes.first?.episodeID == nil)
        #expect(store.removedEpisodes.first?.episodeTitle == "Episode 1")
        #expect(store.removedEpisodes.first?.deviceName == "WALKMAN")
        #expect(viewModel.removedAt(for: laterLoadedEpisode) == removedAt)
    }

    @Test
    func recordDeletedEpisodesPersistsHistoryFromUnknownCurrentFiles() {
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
            deviceName: "WALKMAN",
            removedAt: Date(timeIntervalSince1970: 1_713_800_000)
        )

        #expect(viewModel.removedAt(for: episode) == nil)
        #expect(store.removedEpisodes.count == 1)
        #expect(store.removedEpisodes.first?.episodeTitle == "Unknown")
    }

    @Test
    func removedRecordMatchesWhenFeedTitleChangesAfterDeletion() {
        let subscriptionID = UUID(uuidString: "BECA0000-0000-0000-0000-000000000001")!
        let removedAt = Date(timeIntervalSince1970: 1_716_500_000)
        let deletedPublicationDate = makeDate(year: 2026, month: 5, day: 20, hour: 0, minute: 0)
        let currentPublicationDate = makeDate(year: 2026, month: 5, day: 20, hour: 21, minute: 39)
        let store = InMemoryRemovedEpisodeStore()
        store.removedEpisodes = [
            RemovedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: nil,
                fileStem: "2026.05.20-David Sinclair's Transvulcania Victory, Cocodona Viewership Numbers, & the State of Live Streaming-(The Freetrail Podcast with Dylan Bowman)",
                episodeTitle: "David Sinclair's Transvulcania Victory, Cocodona Viewership Numbers, & the State of Live Streaming",
                publicationDate: deletedPublicationDate,
                deviceName: "WALKMAN",
                removedAt: removedAt
            )
        ]
        let viewModel = RemovedEpisodeHistoryViewModel(store: store)
        viewModel.load()

        let currentFeedEpisode = Episode(
            id: "f13f98bc-c872-459f-ad59-c8200210d878",
            subscriptionID: subscriptionID,
            podcastTitle: "The Freetrail Podcast with Dylan Bowman",
            title: "David Sinclair Interview, Cocodona Viewership Stats, & the State of Trail Race Live Streaming",
            publicationDate: currentPublicationDate,
            enclosureURL: URL(string: "https://example.com/david-sinclair.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        #expect(viewModel.removedAt(for: currentFeedEpisode) == removedAt)
    }

    @Test
    func recordDeletedEpisodesStoresCurrentEpisodeIDWhenDeletedTitleHasChanged() {
        let subscriptionID = UUID(uuidString: "BECA0000-0000-0000-0000-000000000001")!
        let removedAt = Date(timeIntervalSince1970: 1_716_500_000)
        let currentFeedEpisode = Episode(
            id: "f13f98bc-c872-459f-ad59-c8200210d878",
            subscriptionID: subscriptionID,
            podcastTitle: "The Freetrail Podcast with Dylan Bowman",
            title: "David Sinclair Interview, Cocodona Viewership Stats, & the State of Trail Race Live Streaming",
            publicationDate: makeDate(year: 2026, month: 5, day: 20, hour: 21, minute: 39),
            enclosureURL: URL(string: "https://example.com/david-sinclair.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        let store = InMemoryRemovedEpisodeStore()
        let viewModel = RemovedEpisodeHistoryViewModel(store: store)
        let deletedTargetURL = URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC/The Freetrail Podcast with Dylan Bowman/2026.05.20-David Sinclair's Transvulcania Victory, Cocodona Viewership Numbers, & the State of Live Streaming-(The Freetrail Podcast with Dylan Bowman).mp3")

        viewModel.recordDeletedEpisodes(
            deletedTargetURLs: [deletedTargetURL],
            filesBySubscriptionID: [subscriptionID: [deletedTargetURL]],
            episodesBySubscriptionID: [subscriptionID: [currentFeedEpisode]],
            deviceName: "WALKMAN",
            removedAt: removedAt
        )

        #expect(store.removedEpisodes.first?.episodeID == currentFeedEpisode.id)
        #expect(viewModel.removedAt(for: currentFeedEpisode) == removedAt)
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

private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}
