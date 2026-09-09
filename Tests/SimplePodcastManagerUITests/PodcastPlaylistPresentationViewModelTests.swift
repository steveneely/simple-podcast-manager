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
