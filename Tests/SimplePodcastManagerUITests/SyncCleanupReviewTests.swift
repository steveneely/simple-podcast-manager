import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncCleanupReviewTests {
    private let subscription = PodcastSubscription(
        title: "Example Podcast", rssURL: URL(string: "https://example.invalid/rss")!
    )
    private let device = DeviceInfo(
        name: "Synthetic Device", rootURL: URL(fileURLWithPath: "/Volumes/Synthetic"),
        podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/Synthetic/music")
    )

    private func candidate(_ title: String) -> DeviceCleanupCandidate {
        DeviceCleanupCandidate(
            targetURL: device.podcastDirectoryURL.appending(path: "Example Podcast/2026.01.01-\(title)-(Example Podcast).mp3"),
            subscriptionID: subscription.id, podcastTitle: subscription.title,
            episodeTitle: title, publicationDate: Date(timeIntervalSince1970: 1_767_225_600),
            fileSizeBytes: 1_024
        )
    }

    private func deviceEpisode(for candidate: DeviceCleanupCandidate) throws -> Episode {
        try #require(SyncCleanupReview().episode(
            for: candidate, subscriptions: [subscription], knownEpisodes: [], deviceFile: { _ in nil }
        ))
    }

    @Test
    func playlistChangesPersistAndOnlyClearTheChosenDeletionAfterSuccess() async throws {
        let store = CleanupPlaylistStore()
        let playlists = PodcastPlaylistViewModel(store: store)
        await playlists.load()
        let playlistID = try playlists.createPlaylist(named: "Listen Later")
        let target = candidate("Old Episode")
        let other = candidate("Other Episode").id
        var review = SyncCleanupReview()
        let episode = try deviceEpisode(for: target)
        var excluded: Set<URL> = []
        var manual: Set<URL> = [target.id, other]
        var protected: Set<URL> = [target.id, other]
        func togglePlaylist() throws -> Bool {
            review.togglePlaylist(
                for: episode, candidate: target, playlist: try #require(playlists.playlist(id: playlistID)),
                playlists: playlists, excludedCleanupTargets: &excluded,
                manualDeletionTargets: &manual, protectedDeletionTargets: &protected
            )
        }
        store.failSaves = true
        #expect(try !togglePlaylist())
        #expect(review.lastErrorMessage != nil)
        #expect(excluded.isEmpty)
        #expect(manual == [target.id, other])
        #expect(protected == [target.id, other])
        #expect(playlists.playlist(id: playlistID)?.contains(episode) == false)

        store.failSaves = false
        #expect(try togglePlaylist())
        #expect(review.lastErrorMessage == nil)
        #expect(excluded == [target.id])
        #expect(manual == [other])
        #expect(protected == [other])
        let reloaded = PodcastPlaylistViewModel(store: store)
        await reloaded.load()
        #expect(reloaded.playlist(id: playlistID)?.contains(episode) == true)

        #expect(try togglePlaylist())
        #expect(excluded == [target.id])
        #expect(playlists.playlist(id: playlistID)?.contains(episode) == false)
    }

    @Test
    func playlistProtectionKeepsRowsInPlaceUntilTheNextReview() throws {
        let first = candidate("First")
        let second = candidate("Second")
        var review = SyncCleanupReview()
        review.update(plan: SyncPlan(device: device, actions: [], cleanupCandidates: [first, second]))
        let episode = try deviceEpisode(for: first)
        let plan = SyncPlan(
            device: device, actions: [], cleanupCandidates: [second],
            playlistProtectedCleanupCandidates: [PlaylistProtectedCleanupCandidate(
                targetURL: first.targetURL, episode: episode, publicationDate: first.publicationDate,
                fileSizeBytes: first.fileSizeBytes, playlistNames: ["Listen Later"]
            )]
        )
        review.update(plan: plan)
        #expect(review.candidates == [first, second])
        var nextReview = SyncCleanupReview()
        nextReview.update(plan: plan)
        #expect(nextReview.candidates == [second])
        review.update(plan: SyncPlan(device: device, actions: []))
        #expect(review.candidates.isEmpty)
    }

    @Test
    func resolvesKnownEpisodesAndUsesExistingDeviceOnlyIdentityWhenAbsent() throws {
        let target = candidate("Old Episode")
        let review = SyncCleanupReview()
        let fallback = try deviceEpisode(for: target)
        #expect(fallback.id == "device-file::\(target.targetURL.lastPathComponent)")
        #expect(fallback.enclosureURL == target.targetURL)
        var known = fallback
        known.id = "rss-episode-id"
        known.enclosureURL = URL(string: "https://example.invalid/episode.mp3")!
        #expect(review.episode(
            for: target, subscriptions: [subscription], knownEpisodes: [known],
            deviceFile: { _ in target.targetURL }
        ) == known)
        #expect(review.episode(
            for: target, subscriptions: [], knownEpisodes: [], deviceFile: { _ in nil }
        ) == nil)
    }
}

private final class CleanupPlaylistStore: PodcastPlaylistStore, @unchecked Sendable {
    var library = PodcastPlaylistLibrary()
    var failSaves = false
    func loadPodcastPlaylistLibrary() throws -> PodcastPlaylistLibrary { library }
    func savePodcastPlaylistLibrary(_ library: PodcastPlaylistLibrary) throws {
        if failSaves { throw CocoaError(.fileWriteUnknown) }
        self.library = library
    }
}
