import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastPlaylistViewModelTests {
    @Test
    func createsOrdersAndRemovesPlaylistEntries() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Commute")
        let first = makeEpisode(id: "first", title: "First")
        let second = makeEpisode(id: "second", title: "Second")

        try viewModel.add(first, to: playlistID)
        try viewModel.add(second, to: playlistID)
        try viewModel.moveEntry(in: playlistID, from: 1, to: 0)
        try viewModel.remove(first, from: playlistID)

        #expect(viewModel.playlist(id: playlistID)?.entries.map(\.episode.id) == ["second"])
        #expect(store.library == viewModel.library)
    }

    @Test
    func dragMovePreservesTheRelativeOrderOfMovedEntries() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Commute")
        for id in ["first", "second", "third", "fourth"] {
            try viewModel.add(makeEpisode(id: id, title: id.capitalized), to: playlistID)
        }

        try viewModel.moveEntries(in: playlistID, from: IndexSet([1, 2]), to: 4)

        #expect(viewModel.playlist(id: playlistID)?.entries.map(\.episode.id) == [
            "first", "fourth", "second", "third",
        ])
    }

    @Test
    func renameKeepsOldOwnedFileAsDeletionTombstoneUntilSyncCompletes() async throws {
        let original = try PodcastPlaylist(name: "Commute")
        let store = InMemoryPodcastPlaylistStore(library: PodcastPlaylistLibrary(
            playlists: [original],
            deviceStates: [
                "walkman": PodcastPlaylistDeviceState(ownedDeviceFileNames: ["Commute.m3u"])
            ]
        ))
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.renamePlaylist(id: original.id, to: "Garden")

        #expect(viewModel.library.deviceStates["walkman"]?.pendingDeletedDeviceFileNames == ["Commute.m3u"])
        try viewModel.markDevicePlaylistSyncCompleted(deviceID: "walkman")
        #expect(viewModel.library.deviceStates["walkman"] == PodcastPlaylistDeviceState(
            ownedDeviceFileNames: ["Garden.m3u"],
            pendingDeletedDeviceFileNames: []
        ))
    }

    @Test
    func downloadedEpisodesAccumulateWithoutDuplicatesAndSurviveReloading() async throws {
        let first = makeEpisode(id: "first", title: "First")
        let second = makeEpisode(id: "second", title: "Second")
        let olderPreparedEpisode = makeEpisode(id: "older", title: "Older")
        let playlist = try PodcastPlaylist(
            name: "Recently Downloaded",
            automaticRule: PodcastPlaylistAutomaticRule(source: .recentlyDownloaded)
        )
        let store = InMemoryPodcastPlaylistStore(library: PodcastPlaylistLibrary(
            playlists: [playlist],
            recentlyDownloadedEntries: [try #require(PodcastPlaylistEntry(episode: first))]
        ))
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.recordDownloadedEpisodes([second, second])

        #expect(viewModel.library.recentlyDownloadedEntries.map(\.episode.id) == [
            "second", "first",
        ])
        #expect(viewModel.playlists(containing: second).map(\.id) == [playlist.id])

        try viewModel.seedRecentlyDownloadedEpisodes([olderPreparedEpisode, first])
        #expect(viewModel.library.recentlyDownloadedEntries.map(\.episode.id) == [
            "second", "first", "older",
        ])

        let reloadedViewModel = PodcastPlaylistViewModel(store: store)
        await reloadedViewModel.load()
        #expect(reloadedViewModel.library.recentlyDownloadedEntries.map(\.episode.id) == [
            "second", "first", "older",
        ])
    }

    @Test
    func rejectsDuplicateNamesCaseInsensitively() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        _ = try viewModel.createPlaylist(named: "Commute")

        #expect(throws: PodcastPlaylistError.duplicateName) {
            try viewModel.createPlaylist(named: "commute")
        }
    }

    @Test
    func configuresAutomaticAdditionsOnAnExistingPlaylist() async throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Latest")

        try viewModel.updatePlaylist(
            id: playlistID,
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .selectedPodcasts([podcastID]),
                maximumEpisodeCount: 10
            )
        )

        #expect(viewModel.playlist(id: playlistID)?.automaticRule == PodcastPlaylistAutomaticRule(
            source: .selectedPodcasts([podcastID]),
            maximumEpisodeCount: 10
        ))
        #expect(viewModel.playlist(id: playlistID)?.name == "News")
        #expect(store.library == viewModel.library)
    }

    @Test
    func createsPlaylistWithAutomaticSettings() async throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let rule = PodcastPlaylistAutomaticRule(
            source: .selectedPodcasts([podcastID]),
            maximumEpisodeCount: 15
        )

        let playlistID = try viewModel.createPlaylist(
            named: "News",
            automaticRule: rule
        )

        #expect(viewModel.playlist(id: playlistID)?.automaticRule == rule)
        #expect(store.library == viewModel.library)
    }

    @Test
    func editorPresentationRetainsAutomaticSettings() throws {
        let rule = PodcastPlaylistAutomaticRule(maximumEpisodeCount: 20)
        let playlist = try PodcastPlaylist(name: "Latest", automaticRule: rule)

        let presentation = PodcastPlaylistEditorPresentation(playlist: playlist)

        #expect(presentation.playlistID == playlist.id)
        #expect(presentation.initialName == "Latest")
        #expect(presentation.automaticRule == rule)
    }

    @Test
    func automaticallyPopulatedPlaylistStillAcceptsExplicitEntries() async throws {
        let episode = makeEpisode(id: "episode", title: "Episode")
        let exclusion = try #require(PodcastPlaylistAutomaticExclusion(episode: episode))
        let playlist = try PodcastPlaylist(
            name: "Everything",
            automaticRule: PodcastPlaylistAutomaticRule(),
            automaticExclusions: [exclusion]
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(playlists: [playlist])
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.add(episode, to: playlist.id)

        #expect(viewModel.playlist(id: playlist.id)?.entries.map(\.episode.id) == ["episode"])
        #expect(viewModel.playlist(id: playlist.id)?.automaticExclusions.isEmpty == true)
    }

    @Test
    func excludesAnAutomaticEpisodeWithoutRemovingItsDownload() async throws {
        let playlist = try PodcastPlaylist(
            name: "Everything",
            automaticRule: PodcastPlaylistAutomaticRule()
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(playlists: [playlist])
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let episode = makeEpisode(id: "episode", title: "Episode")
        let deviceFileURL = URL(fileURLWithPath: "/Volumes/WALKMAN/music/Example Podcast/old-name.mp3")

        try viewModel.excludeAutomaticEpisode(
            episode,
            from: playlist.id,
            deviceFileURL: deviceFileURL
        )

        #expect(viewModel.playlist(id: playlist.id)?.automaticExclusions == [
            try #require(PodcastPlaylistAutomaticExclusion(episode: episode)),
            PodcastPlaylistAutomaticExclusion(
                subscriptionID: try #require(episode.subscriptionID),
                episodeFileStem: "old-name"
            ),
        ])
    }

    @Test
    func automaticSettingsRejectAnEmptySelectedPodcastRule() async throws {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let playlistID = try viewModel.createPlaylist(named: "Nothing")

        #expect(throws: PodcastPlaylistError.automaticPlaylistNeedsPodcast) {
            try viewModel.updatePlaylist(
                id: playlistID,
                name: "Nothing",
                automaticRule: PodcastPlaylistAutomaticRule(source: .selectedPodcasts([]))
            )
        }
        #expect(throws: PodcastPlaylistError.automaticPlaylistNeedsPodcast) {
            try viewModel.createPlaylist(
                named: "Also Nothing",
                automaticRule: PodcastPlaylistAutomaticRule(source: .selectedPodcasts([]))
            )
        }
    }

    @Test
    func deletingLastSelectedPodcastLeavesAutomaticRuleScopedToNoPodcasts() async throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let playlist = try PodcastPlaylist(
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule(source: .selectedPodcasts([podcastID]))
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(playlists: [playlist])
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.removeEntries(forSubscriptionIDs: [podcastID])

        #expect(viewModel.playlist(id: playlist.id)?.automaticRule?.source == .selectedPodcasts([]))
    }

    private func makeEpisode(id: String, title: String) -> Episode {
        Episode(
            id: id,
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "Example Podcast",
            title: title,
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
    }
}

private final class InMemoryPodcastPlaylistStore: PodcastPlaylistStore, @unchecked Sendable {
    var library: PodcastPlaylistLibrary

    init(library: PodcastPlaylistLibrary = PodcastPlaylistLibrary()) {
        self.library = library
    }

    func loadPodcastPlaylistLibrary() throws -> PodcastPlaylistLibrary {
        library
    }

    func savePodcastPlaylistLibrary(_ library: PodcastPlaylistLibrary) throws {
        self.library = library
    }
}
