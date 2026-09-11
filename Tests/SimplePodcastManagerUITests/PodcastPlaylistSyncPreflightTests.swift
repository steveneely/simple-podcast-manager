import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastPlaylistSyncPreflightTests {
    @Test
    func findsOnlyUnavailableManualEntries() throws {
        let availableEpisode = makeEpisode(id: "available", title: "Available")
        let unavailableEpisode = makeEpisode(id: "unavailable", title: "Unavailable")
        let automaticEpisode = makeEpisode(id: "automatic", title: "Automatic")
        let playlist = try PodcastPlaylist(
            name: "News",
            entries: [
                try #require(PodcastPlaylistEntry(episode: availableEpisode)),
                try #require(PodcastPlaylistEntry(episode: unavailableEpisode)),
            ],
            automaticRule: PodcastPlaylistAutomaticRule()
        )

        let preflight = PodcastPlaylistSyncPreflight.make(
            playlists: [playlist],
            isAvailable: { $0.id == availableEpisode.id || $0.id == automaticEpisode.id }
        )

        #expect(preflight?.unavailableEpisodes == [unavailableEpisode])
        #expect(preflight?.affectedPlaylistNames == ["News"])
        #expect(preflight?.title == "Download Playlist Episode?")
        #expect(preflight?.message == "“News” contains “Unavailable,” which is unavailable. Download it so it can be included when you sync?")
    }

    @Test
    func deduplicatesAnEpisodeSharedBySeveralPlaylists() throws {
        let episode = makeEpisode(id: "shared", title: "Shared")
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        let news = try PodcastPlaylist(name: "News", entries: [entry])
        let commute = try PodcastPlaylist(name: "Commute", entries: [entry])

        let preflight = PodcastPlaylistSyncPreflight.make(
            playlists: [news, commute],
            isAvailable: { _ in false }
        )

        #expect(preflight?.unavailableEpisodes == [episode])
        #expect(preflight?.affectedPlaylistNames == ["News", "Commute"])
    }

    @Test
    func summarizesSeveralUnavailableEpisodeTitlesBriefly() throws {
        let first = makeEpisode(id: "first", title: "First")
        let second = makeEpisode(id: "second", title: "Second")
        let third = makeEpisode(id: "third", title: "Third")
        let playlist = try PodcastPlaylist(
            name: "News",
            entries: try [first, second, third].map {
                try #require(PodcastPlaylistEntry(episode: $0))
            }
        )

        let preflight = PodcastPlaylistSyncPreflight.make(
            playlists: [playlist],
            isAvailable: { _ in false }
        )

        #expect(preflight?.message == "“News” contains 3 unavailable manually added episodes: “First” and “Second”, and 1 more. Download them so they can be included when you sync?")
    }

    @Test
    func returnsNoPreflightWhenEveryManualEntryIsAvailable() throws {
        let episode = makeEpisode(id: "available", title: "Available")
        let playlist = try PodcastPlaylist(
            name: "News",
            entries: [try #require(PodcastPlaylistEntry(episode: episode))]
        )

        let preflight = PodcastPlaylistSyncPreflight.make(
            playlists: [playlist],
            isAvailable: { _ in true }
        )

        #expect(preflight == nil)
    }

    @Test
    func downloadFailureExplainsThatSyncWillSkipTheEpisode() {
        let episode = makeEpisode(id: "missing", title: "Missing Episode")
        let failure = PodcastPlaylistSyncDownloadFailure(
            unavailableEpisodes: [episode],
            detail: "Download failed."
        )

        #expect(failure.title == "Episode Couldn’t Be Downloaded")
        #expect(failure.message == "“Missing Episode” remains unavailable and will not be included when you sync. Download failed.")
    }
}

private func makeEpisode(id: String, title: String) -> Episode {
    Episode(
        id: id,
        subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        podcastTitle: "Example Podcast",
        title: title,
        publicationDate: Date(timeIntervalSince1970: 1_700_000_000),
        enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
        sourceFeedURL: URL(string: "https://example.com/feed.xml")!
    )
}
