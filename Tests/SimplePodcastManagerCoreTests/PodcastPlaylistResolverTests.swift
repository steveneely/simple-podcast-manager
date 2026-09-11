import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct PodcastPlaylistResolverTests {
    @Test
    func combinesExplicitEntriesWithNewestAutomaticMatches() throws {
        let includedPodcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let excludedPodcastID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let pinned = makeEpisode(id: "pinned", podcastID: includedPodcastID, day: 1)
        let playlist = try PodcastPlaylist(
            name: "News",
            entries: [try #require(PodcastPlaylistEntry(episode: pinned))],
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .selectedPodcasts([includedPodcastID]),
                maximumEpisodeCount: 2
            )
        )
        let episodes = [
            pinned,
            makeEpisode(id: "new", podcastID: includedPodcastID, day: 4),
            makeEpisode(id: "middle", podcastID: includedPodcastID, day: 3),
            makeEpisode(id: "excluded", podcastID: excludedPodcastID, day: 5),
        ]

        let entries = PodcastPlaylistResolver.entries(for: playlist, from: episodes)

        #expect(entries.explicit.map(\.episode.id) == ["pinned"])
        #expect(entries.automatic.map(\.episode.id) == ["new", "middle"])
        #expect(entries.all.map(\.episode.id) == ["pinned", "new", "middle"])
    }

    @Test
    func automaticExclusionKeepsAMatchOut() throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let excludedEpisode = makeEpisode(id: "excluded", podcastID: podcastID, day: 2)
        let playlist = try PodcastPlaylist(
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule(),
            automaticExclusions: [try #require(
                PodcastPlaylistAutomaticExclusion(episode: excludedEpisode)
            )]
        )

        let entries = PodcastPlaylistResolver.entries(
            for: playlist,
            from: [excludedEpisode, makeEpisode(id: "included", podcastID: podcastID, day: 1)]
        )

        #expect(entries.automatic.map(\.episode.id) == ["included"])
    }

    @Test
    func recentlyDownloadedUsesPersistentDownloadOrderEvenWhenMediaIsUnavailable() throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let newest = makeEpisode(id: "newest", podcastID: podcastID, day: 4)
        let older = makeEpisode(id: "older", podcastID: podcastID, day: 2)
        let noLongerAvailable = makeEpisode(id: "removed", podcastID: podcastID, day: 3)
        let notInTheSnapshot = makeEpisode(id: "unrelated", podcastID: podcastID, day: 5)
        let playlist = try PodcastPlaylist(
            name: "Fresh from Sync",
            automaticRule: PodcastPlaylistAutomaticRule(source: .recentlyDownloaded)
        )

        let entries = PodcastPlaylistResolver.entries(
            for: playlist,
            from: [older, newest, notInTheSnapshot],
            recentlyDownloadedEntries: [older, newest, noLongerAvailable].compactMap(
                PodcastPlaylistEntry.init(episode:)
            )
        )

        #expect(entries.automatic.map(\.episode.id) == ["older", "newest", "removed"])
    }

    @Test
    func recentlyDownloadedLimitCapsAutomaticEntriesInDownloadOrder() throws {
        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let firstDownload = makeEpisode(id: "first", podcastID: podcastID, day: 1)
        let secondDownload = makeEpisode(id: "second", podcastID: podcastID, day: 3)
        let thirdDownload = makeEpisode(id: "third", podcastID: podcastID, day: 2)
        let downloads = [firstDownload, secondDownload, thirdDownload]
        let playlist = try PodcastPlaylist(
            name: "Recently Downloaded",
            automaticRule: PodcastPlaylistAutomaticRule(
                source: .recentlyDownloaded,
                maximumEpisodeCount: 2
            )
        )

        let entries = PodcastPlaylistResolver.entries(
            for: playlist,
            from: downloads,
            recentlyDownloadedEntries: downloads.compactMap(PodcastPlaylistEntry.init(episode:))
        )

        #expect(entries.automatic.map(\.episode.id) == ["first", "second"])
    }

    @Test
    func oldPlaylistJSONDecodesWithUnifiedDefaults() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Commute",
          "deviceFileName": "Commute.m3u",
          "entries": []
        }
        """

        let playlist = try JSONDecoder().decode(PodcastPlaylist.self, from: Data(json.utf8))

        #expect(!playlist.automaticallyAddsEpisodes)
        #expect(playlist.automaticRule == nil)
        #expect(playlist.automaticExclusions.isEmpty)
        #expect(playlist.icon == .music)
    }

    @Test
    func selectedPlaylistIconSurvivesJSONRoundTrip() throws {
        let playlist = try PodcastPlaylist(name: "Cycling", icon: .cycling)

        let data = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(PodcastPlaylist.self, from: data)

        #expect(decoded.icon == .cycling)
    }

    @Test
    func oldDeviceStateJSONDecodesWithAnEmptyMostRecentSyncSnapshot() throws {
        let json = """
        {
          "ownedDeviceFileNames": ["Commute.m3u"],
          "pendingDeletedDeviceFileNames": []
        }
        """

        let state = try JSONDecoder().decode(PodcastPlaylistDeviceState.self, from: Data(json.utf8))

        #expect(state.ownedDeviceFileNames == ["Commute.m3u"])
        #expect(state.playlistDirectoryPath == nil)
        #expect(state.mostRecentSyncEntries.isEmpty)
    }

    @Test
    func developmentMostRecentSyncDataMigratesToRecentlyDownloaded() throws {
        let sourceJSON = """
        { "kind": "mostRecentSync" }
        """
        let source = try JSONDecoder().decode(
            PodcastPlaylistAutomaticSource.self,
            from: Data(sourceJSON.utf8)
        )
        #expect(source == .recentlyDownloaded)

        let podcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let entry = try #require(PodcastPlaylistEntry(
            episode: makeEpisode(id: "downloaded", podcastID: podcastID, day: 2)
        ))
        let legacyLibrary = LegacyPlaylistLibrary(
            playlists: [],
            deviceStates: [
                "walkman": PodcastPlaylistDeviceState(mostRecentSyncEntries: [entry])
            ]
        )

        let data = try JSONEncoder().encode(legacyLibrary)
        let migratedLibrary = try JSONDecoder().decode(PodcastPlaylistLibrary.self, from: data)

        #expect(migratedLibrary.recentlyDownloadedEntries == [entry])
    }

    @Test
    func developmentSmartRuleJSONMigratesToAutomaticRule() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "News",
          "deviceFileName": "News.m3u",
          "entries": [],
          "smartRule": {
            "source": { "kind": "allPodcasts" },
            "maximumEpisodeCount": 12
          }
        }
        """

        let playlist = try JSONDecoder().decode(PodcastPlaylist.self, from: Data(json.utf8))

        #expect(playlist.automaticRule == PodcastPlaylistAutomaticRule(maximumEpisodeCount: 12))
    }

    private func makeEpisode(
        id: String,
        podcastID: PodcastSubscription.ID,
        day: Int
    ) -> Episode {
        Episode(
            id: id,
            subscriptionID: podcastID,
            podcastTitle: "Podcast \(podcastID.uuidString.prefix(4))",
            title: id.capitalized,
            publicationDate: ISO8601DateFormatter().date(
                from: "2026-09-0\(day)T00:00:00Z"
            ),
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
    }
}

private struct LegacyPlaylistLibrary: Encodable {
    var playlists: [PodcastPlaylist]
    var deviceStates: [String: PodcastPlaylistDeviceState]
}
