import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastPlaylistPresentationViewModelTests {
    @Test
    func builderResolvesPreparedAndDeviceEpisodesOutsideTheRenderPath() throws {
        let subscription = PodcastSubscription(
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Player",
            rootURL: URL(fileURLWithPath: "/Volumes/PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/PLAYER/music", isDirectory: true)
        )
        let directory = device.podcastDirectoryURL.appendingPathComponent(
            subscription.title,
            isDirectory: true
        )
        let current = makeEpisode(
            id: "current",
            title: "Current",
            day: 2,
            subscription: subscription
        )
        let prepared = makeEpisode(
            id: "prepared",
            title: "Prepared",
            day: 3,
            subscription: subscription
        )
        let currentFile = directory.appendingPathComponent(
            EpisodeFileName.fileName(for: current, fileExtension: "mp3")
        )
        let removedOlderFile = directory.appendingPathComponent(
            "2026.09.01-Older-(Example Podcast).mp3"
        )
        let inventory = ManagedDeviceLibraryInventory(
            device: device,
            subscriptions: [subscription],
            managedDirectoryURLsBySubscriptionID: [subscription.id: directory],
            filesBySubscriptionID: [subscription.id: [currentFile, removedOlderFile]]
        )
        let playlist = try PodcastPlaylist(
            name: "News",
            automaticRule: PodcastPlaylistAutomaticRule()
        )

        let presentation = PodcastPlaylistPresentationBuilder.build(
            playlists: [playlist],
            subscriptions: [subscription],
            episodes: [current, prepared],
            preparedEpisodeIDs: [try #require(PodcastPlaylistEpisodeID(episode: prepared))],
            recentlyDownloadedEntries: [],
            managedInventory: inventory,
            plannedRemovalURLs: [removedOlderFile.standardizedFileURL],
            replacementTargets: []
        )

        #expect(presentation.entriesByPlaylistID[playlist.id]?.automatic.map(\.episode.id) == [
            "prepared", "current",
        ])
        #expect(presentation.episodeCountsByPlaylistID[playlist.id] == 2)
        #expect(presentation.automaticPlaylistIDs(containing: prepared) == [playlist.id])
    }

    @Test
    func episodeIndicatorDistinguishesManualAutomaticAndMissingMemberships() throws {
        let subscription = PodcastSubscription(
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let episode = makeEpisode(
            id: "included",
            title: "Included",
            day: 2,
            subscription: subscription
        )
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        let manualPlaylist = try PodcastPlaylist(name: "Saved", entries: [entry])
        let automaticPlaylist = try PodcastPlaylist(name: "News")
        let unrelatedPlaylist = try PodcastPlaylist(name: "Commute")

        let presentation = EpisodePlaylistIndicatorPresentation(
            episode: episode,
            playlists: [manualPlaylist, automaticPlaylist, unrelatedPlaylist],
            automaticPlaylistIDs: [automaticPlaylist.id]
        )

        #expect(presentation.isIncluded)
        #expect(presentation.systemName == "text.badge.checkmark")
        #expect(presentation.helpText == "In 2 playlists — click to manage")
        #expect(presentation.membership(for: manualPlaylist.id) == .manual)
        #expect(presentation.membership(for: automaticPlaylist.id) == .automatic)
        #expect(presentation.membership(for: unrelatedPlaylist.id) == .none)
    }

    @Test
    func episodeIndicatorNamesOnePlaylistAndUsesAddStateForNone() throws {
        let subscription = PodcastSubscription(
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let episode = makeEpisode(
            id: "included",
            title: "Included",
            day: 2,
            subscription: subscription
        )
        let playlist = try PodcastPlaylist(name: "News")

        let included = EpisodePlaylistIndicatorPresentation(
            episode: episode,
            playlists: [playlist],
            automaticPlaylistIDs: [playlist.id]
        )
        let notIncluded = EpisodePlaylistIndicatorPresentation(
            episode: episode,
            playlists: [playlist],
            automaticPlaylistIDs: []
        )

        #expect(included.helpText == "In playlist “News” — click to manage")
        #expect(notIncluded.systemName == "text.badge.plus")
        #expect(notIncluded.helpText == "Add to playlist")
        #expect(!notIncluded.isIncluded)
    }

    @Test
    func detailEntriesReflectAPinBeforeAutomaticPresentationRefreshFinishes() throws {
        let subscription = PodcastSubscription(
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let episode = makeEpisode(
            id: "automatic",
            title: "Automatic",
            day: 2,
            subscription: subscription
        )
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        var playlist = try PodcastPlaylist(name: "News")
        let stalePresentation = PodcastPlaylistPresentation(
            entriesByPlaylistID: [
                playlist.id: ResolvedPodcastPlaylistEntries(
                    explicit: [],
                    automatic: [entry]
                ),
            ],
            episodeCountsByPlaylistID: [playlist.id: 1]
        )

        playlist.entries.append(entry)
        let entries = stalePresentation.entries(reflecting: playlist)

        #expect(entries.explicit == [entry])
        #expect(entries.automatic.isEmpty)
        #expect(entries.all == [entry])
    }

    @Test
    func builderKeepsRecentlyDownloadedEntriesVisibleWithoutAConnectedDevice() throws {
        let subscription = PodcastSubscription(
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let downloadedEpisode = makeEpisode(
            id: "downloaded",
            title: "Downloaded",
            day: 2,
            subscription: subscription
        )
        let downloadedEntry = try #require(PodcastPlaylistEntry(episode: downloadedEpisode))
        let playlist = try PodcastPlaylist(
            name: "Recently Downloaded",
            automaticRule: PodcastPlaylistAutomaticRule(source: .recentlyDownloaded)
        )

        let presentation = PodcastPlaylistPresentationBuilder.build(
            playlists: [playlist],
            subscriptions: [subscription],
            episodes: [],
            preparedEpisodeIDs: [],
            recentlyDownloadedEntries: [downloadedEntry],
            managedInventory: nil,
            plannedRemovalURLs: [],
            replacementTargets: []
        )

        #expect(presentation.entriesByPlaylistID[playlist.id]?.automatic == [downloadedEntry])
        #expect(presentation.episodeCountsByPlaylistID[playlist.id] == 1)
    }

    private func makeEpisode(
        id: String,
        title: String,
        day: Int,
        subscription: PodcastSubscription
    ) -> Episode {
        Episode(
            id: id,
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: title,
            publicationDate: ISO8601DateFormatter().date(from: "2026-09-0\(day)T00:00:00Z"),
            enclosureURL: URL(string: "https://example.com/\(id).mp3")!,
            sourceFeedURL: subscription.rssURL
        )
    }
}
