import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct FeedRefreshSummaryTests {
    @Test
    func downloadStatusIdentifiesAutomaticDownloads() {
        #expect(DownloadStatusPresentation.text(count: 2, isAutomatic: true) == "2 automatic downloads")
        #expect(DownloadStatusPresentation.text(count: 1, isAutomatic: false) == "1 downloading")
    }

    @Test
    func allShowsSummaryReportsNewAndDownloadedEpisodes() {
        let summary = FeedRefreshSummary(
            scope: .allShows,
            discoveredEpisodeCount: 3,
            downloadedEpisodes: [download("First", show: "Show A"), download("Second", show: "Show B")],
            failedSubscriptionCount: 0
        )

        #expect(summary.text == "3 new episodes · 2 downloaded")
        #expect(summary.downloadedEpisodes.map(\.episodeTitle) == ["First", "Second"])
    }

    @Test
    func noChangesSummaryConfirmsRefreshCompleted() {
        let summary = FeedRefreshSummary(
            scope: .allShows,
            discoveredEpisodeCount: 0,
            downloadedEpisodes: [],
            failedSubscriptionCount: 0
        )

        #expect(summary.text == "No new episodes")
    }

    @Test
    func individualShowSummaryNamesShowAndReportsFailures() {
        let summary = FeedRefreshSummary(
            scope: .show("Example Show"),
            discoveredEpisodeCount: 1,
            downloadedEpisodes: [],
            failedSubscriptionCount: 1
        )

        #expect(summary.text == "Example Show: 1 new episode · 0 downloaded · 1 show failed")
    }

    private func download(_ title: String, show: String) -> FeedRefreshDownloadedEpisode {
        FeedRefreshDownloadedEpisode(Episode(
            id: title,
            subscriptionID: UUID(),
            podcastTitle: show,
            title: title,
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        ))
    }
}
