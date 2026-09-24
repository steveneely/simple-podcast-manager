import AppKit
import SwiftUI
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncDialogLayoutTests {
    @Test
    func crowdedReviewOpensPlannedActionsInOneLargeScrollingArea() throws {
        let root = URL(fileURLWithPath: "/Volumes/SyntheticReview")
        let podcastID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let candidates = (0..<33).map { index in
            DeviceCleanupCandidate(
                targetURL: root.appending(path: "music/episode-\(index).mp3"),
                subscriptionID: podcastID,
                podcastTitle: "Synthetic Podcast",
                episodeTitle: "Episode \(index)",
                publicationDate: date,
                fileSizeBytes: 1_024
            )
        }
        let protected = PlaylistProtectedCleanupCandidate(
            targetURL: root.appending(path: "music/protected.mp3"),
            episode: Episode(
                id: "protected", subscriptionID: podcastID,
                podcastTitle: "Synthetic Podcast", title: "Saved Episode",
                publicationDate: date,
                enclosureURL: URL(string: "https://example.invalid/episode.mp3")!,
                sourceFeedURL: URL(string: "https://example.invalid/rss")!
            ),
            publicationDate: date, fileSizeBytes: 1_024,
            playlistNames: ["Favorites"]
        )
        let plan = SyncPlan(
            device: DeviceInfo(name: "Synthetic Review", rootURL: root, podcastDirectoryURL: root.appending(path: "music")),
            actions: candidates.map { .deleteFromDevice(targetURL: $0.targetURL, fileSizeBytes: $0.fileSizeBytes) },
            cleanupCandidates: candidates,
            playlistProtectedCleanupCandidates: [protected]
        )
        let dialog = SyncDialogView(
            plan: plan, progress: nil, isSyncing: false, isPlanning: false,
            planningErrorTitle: nil, planningErrorMessage: nil,
            incompleteCopyRecoveryTarget: nil, isReplacementPlanReady: false,
            lastResult: nil, lastErrorMessage: nil,
            preparedEpisodeCount: 0, enabledSubscriptionCount: 1,
            cleanupMaximumEpisodesPerPodcast: 10,
            isPresented: .constant(true), ejectAfterSync: .constant(false),
            deleteDownloadsAfterSync: .constant(false),
            onEjectAfterSyncChange: {}, onDeleteDownloadsAfterSyncChange: {},
            onToggleCleanupDeletion: { _ in }, onTogglePlaylistProtectedDeletion: { _ in },
            onReplaceIncompleteCopy: { _ in }, onSync: {}, cleanupCandidates: candidates
        )
        #expect(!dialog.isCleanupExpanded)
        #expect(!dialog.isPlaylistProtectedExpanded)
        #expect(dialog.isPlannedActionsExpanded)
        let view = NSHostingView(rootView: dialog)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
        defer { window.contentView = nil }
        view.setFrameSize(NSSize(width: 680, height: 720))
        view.layoutSubtreeIfNeeded()
        // SwiftUI resolves lazy document content in a subsequent layout pass.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        view.layoutSubtreeIfNeeded()

        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrollAreas = scrollViews(in: view)
        #expect(scrollAreas.count == 1)
        let review = try #require(scrollAreas.first)
        // The review gets the space formerly divided among three tiny lists.
        #expect(review.contentSize.height >= 250)
        let content = try #require(review.documentView)
        #expect(content.frame.height > review.contentSize.height)
    }
}
