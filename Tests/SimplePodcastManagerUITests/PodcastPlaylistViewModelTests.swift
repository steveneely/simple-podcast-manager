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
        try viewModel.markDevicePlaylistSyncCompleted(
            deviceID: "walkman",
            writtenPlaylistFileNames: ["Garden.m3u"],
            playlistDirectoryPath: "playlist_data"
        )
        #expect(viewModel.library.deviceStates["walkman"] == PodcastPlaylistDeviceState(
            ownedDeviceFileNames: ["Garden.m3u"],
            pendingDeletedDeviceFileNames: [],
            playlistDirectoryPath: "playlist_data"
        ))
    }

    @Test
    func syncCompletionDoesNotMarkEmptyPlaylistsAsDeviceFiles() async throws {
        let playlist = try PodcastPlaylist(name: "Empty")
        let store = InMemoryPodcastPlaylistStore(library: PodcastPlaylistLibrary(
            playlists: [playlist],
            deviceStates: [
                "walkman": PodcastPlaylistDeviceState(ownedDeviceFileNames: ["Empty.m3u"]),
            ]
        ))
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.markDevicePlaylistSyncCompleted(
            deviceID: "walkman",
            writtenPlaylistFileNames: []
        )

        #expect(viewModel.library.deviceStates["walkman"] == PodcastPlaylistDeviceState())
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
            icon: .news,
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
        #expect(viewModel.playlist(id: playlistID)?.icon == .news)
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
            icon: .news,
            automaticRule: rule
        )

        #expect(viewModel.playlist(id: playlistID)?.automaticRule == rule)
        #expect(viewModel.playlist(id: playlistID)?.icon == .news)
        #expect(store.library == viewModel.library)
    }

    @Test
    func editorPresentationRetainsAutomaticSettings() throws {
        let rule = PodcastPlaylistAutomaticRule(maximumEpisodeCount: 20)
        let playlist = try PodcastPlaylist(
            name: "Latest",
            icon: .history,
            automaticRule: rule
        )

        let presentation = PodcastPlaylistEditorPresentation(playlist: playlist)

        #expect(presentation.playlistID == playlist.id)
        #expect(presentation.initialName == "Latest")
        #expect(presentation.initialIcon == .history)
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
    func pinningAnAutomaticEpisodeMovesItOutsideTheAutomaticLimit() async throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let pinnedEpisode = makeEpisode(id: "newest", title: "Newest", day: 2)
        let nextAutomaticEpisode = makeEpisode(id: "next", title: "Next", day: 1)
        let playlist = try PodcastPlaylist(
            name: "Latest",
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .selectedPodcasts([podcastID]),
                maximumEpisodeCount: 1
            )
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(playlists: [playlist])
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        let initialEntries = PodcastPlaylistResolver.entries(
            for: playlist,
            from: [nextAutomaticEpisode, pinnedEpisode]
        )
        #expect(initialEntries.explicit.isEmpty)
        #expect(initialEntries.automatic.map(\.episode.id) == ["newest"])

        try viewModel.add(pinnedEpisode, to: playlist.id)

        let updatedPlaylist = try #require(viewModel.playlist(id: playlist.id))
        let updatedEntries = PodcastPlaylistResolver.entries(
            for: updatedPlaylist,
            from: [nextAutomaticEpisode, pinnedEpisode]
        )
        #expect(updatedEntries.explicit.map(\.episode.id) == ["newest"])
        #expect(updatedEntries.automatic.map(\.episode.id) == ["next"])
        #expect(updatedEntries.all.map(\.episode.id) == ["newest", "next"])
    }

    @Test
    func deletedProtectedEpisodeIsRemovedAndExcludedFromAutomaticPlaylists() async throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let episode = makeEpisode(id: "kept", title: "Kept", day: 1)
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        let manuallyAddedPlaylist = try PodcastPlaylist(
            name: "Keep",
            entries: [entry]
        )
        let automaticPlaylist = try PodcastPlaylist(
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .selectedPodcasts([podcastID])
            )
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(
                playlists: [manuallyAddedPlaylist, automaticPlaylist]
            )
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()
        let deviceFileURL = URL(
            fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/music/Example Podcast/2026.09.01-Kept-(Example Podcast).mp3"
        )
        let candidate = PlaylistProtectedCleanupCandidate(
            targetURL: deviceFileURL,
            episode: episode,
            publicationDate: try #require(episode.publicationDate),
            fileSizeBytes: 10,
            playlistNames: ["Keep", "News"]
        )

        try viewModel.removeDeletedPlaylistEpisodes([candidate])

        #expect(viewModel.playlist(id: manuallyAddedPlaylist.id)?.entries.isEmpty == true)
        let updatedAutomaticPlaylist = try #require(viewModel.playlist(id: automaticPlaylist.id))
        let expectedExclusions: Set<PodcastPlaylistAutomaticExclusion> = [
            PodcastPlaylistAutomaticExclusion(
                subscriptionID: podcastID,
                episodeFileStem: EpisodeFileName.fileStem(for: episode)
            ),
            PodcastPlaylistAutomaticExclusion(
                subscriptionID: podcastID,
                episodeFileStem: deviceFileURL.deletingPathExtension().lastPathComponent
            ),
        ]
        #expect(updatedAutomaticPlaylist.automaticExclusions == expectedExclusions)
        #expect(PodcastPlaylistResolver.entries(
            for: updatedAutomaticPlaylist,
            from: [episode]
        ).automatic.isEmpty)
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
    func newPlaylistsRejectLegacyAutomaticSources() async {
        let store = InMemoryPodcastPlaylistStore()
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        for source in [
            PodcastPlaylistAutomaticSource.allPodcasts,
            PodcastPlaylistAutomaticSource.recentlyDownloaded,
        ] {
            #expect(throws: PodcastPlaylistError.unsupportedAutomaticPlaylistSource) {
                try viewModel.createPlaylist(
                    named: "Unsupported \(source)",
                    automaticRule: PodcastPlaylistAutomaticRule(source: source)
                )
            }
        }
    }

    @Test
    func deletingLastSelectedPodcastTurnsPlaylistBackIntoManualOnly() async throws {
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

        #expect(viewModel.playlist(id: playlist.id)?.automaticRule == nil)
    }

    @Test
    func deletingOneSelectedPodcastPreservesRemainingAutomaticSources() async throws {
        let deletedPodcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let retainedPodcastID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let playlist = try PodcastPlaylist(
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .selectedPodcasts([deletedPodcastID, retainedPodcastID])
            )
        )
        let store = InMemoryPodcastPlaylistStore(
            library: PodcastPlaylistLibrary(playlists: [playlist])
        )
        let viewModel = PodcastPlaylistViewModel(store: store)
        await viewModel.load()

        try viewModel.removeEntries(forSubscriptionIDs: [deletedPodcastID])

        #expect(viewModel.playlist(id: playlist.id)?.automaticRule?.source == .selectedPodcasts([
            retainedPodcastID,
        ]))
    }

    private func makeEpisode(id: String, title: String, day: Int? = nil) -> Episode {
        Episode(
            id: id,
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "Example Podcast",
            title: title,
            publicationDate: day.flatMap {
                ISO8601DateFormatter().date(from: "2026-09-\(String(format: "%02d", $0))T00:00:00Z")
            },
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
