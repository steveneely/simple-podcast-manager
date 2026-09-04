import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastRefreshSummaryTests {
    @Test
    func downloadStatusIdentifiesAutomaticDownloads() {
        #expect(DownloadStatusPresentation.text(count: 2, isAutomatic: true) == "2 automatic downloads")
        #expect(DownloadStatusPresentation.text(count: 1, isAutomatic: false) == "1 downloading")
    }

    @Test
    func allPodcastsSummaryReportsNewAndDownloadedEpisodes() {
        let summary = PodcastRefreshSummary(
            scope: .allPodcasts,
            discoveredEpisodeCount: 3,
            downloadedEpisodes: [download("First", podcast: "Podcast A"), download("Second", podcast: "Podcast B")],
            failedSubscriptionCount: 0
        )

        #expect(summary.text == "3 new episodes · 2 downloaded")
        #expect(summary.downloadedEpisodes.map(\.episodeTitle) == ["First", "Second"])
    }

    @Test
    func directDownloadSummaryOmitsPodcastRefreshLanguage() {
        let summary = PodcastRefreshSummary(
            scope: .podcast("Example Podcast"),
            discoveredEpisodeCount: nil,
            downloadedEpisodes: [download("Downloaded Episode", podcast: "Example Podcast")],
            failedSubscriptionCount: 0
        )

        #expect(summary.text == "Example Podcast: 1 downloaded")
    }

    @Test
    func downloadedEpisodeDetailsMergeWithoutDuplicates() {
        let first = download("First", podcast: "Podcast A")
        let second = download("Second", podcast: "Podcast B")

        let merged = PodcastRefreshDownloadedEpisode.merging(
            [first],
            with: [first, second]
        )

        #expect(merged == [first, second])
    }

    @Test
    func noChangesSummaryConfirmsRefreshCompleted() {
        let summary = PodcastRefreshSummary(
            scope: .allPodcasts,
            discoveredEpisodeCount: 0,
            downloadedEpisodes: [],
            failedSubscriptionCount: 0
        )

        #expect(summary.text == "No new episodes")
    }

    @Test
    func individualPodcastSummaryNamesPodcastAndReportsFailures() {
        let summary = PodcastRefreshSummary(
            scope: .podcast("Example Podcast"),
            discoveredEpisodeCount: 1,
            downloadedEpisodes: [],
            failedSubscriptionCount: 1
        )

        #expect(summary.text == "Example Podcast: 1 new episode · 0 downloaded · 1 podcast failed")
    }

    private func download(_ title: String, podcast: String) -> PodcastRefreshDownloadedEpisode {
        PodcastRefreshDownloadedEpisode(Episode(
            id: title,
            subscriptionID: UUID(),
            podcastTitle: podcast,
            title: title,
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        ))
    }
}
