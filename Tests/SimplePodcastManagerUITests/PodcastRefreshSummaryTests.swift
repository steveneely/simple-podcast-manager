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
            checkedPodcastCount: 120,
            discoveredEpisodeCount: 3,
            downloadedEpisodes: [download("First", podcast: "Podcast A"), download("Second", podcast: "Podcast B")],
            remainingNewEpisodes: [download("Third", podcast: "Podcast C")],
            issues: []
        )

        #expect(summary.text == "120 checked · 3 episodes found · 1 still new · 2 downloaded")
        #expect(summary.parts.map(\.tone) == [.neutral, .discovery, .newEpisodes, .downloaded])
        #expect(summary.downloadedEpisodes.map(\.episodeTitle) == ["First", "Second"])
        #expect(summary.remainingNewEpisodes.map(\.episodeTitle) == ["Third"])
        #expect(summary.hasDetails)
    }

    @Test
    func directDownloadSummaryOmitsPodcastRefreshLanguage() {
        let summary = PodcastRefreshSummary(
            scope: .podcast("Example Podcast"),
            checkedPodcastCount: nil,
            discoveredEpisodeCount: nil,
            downloadedEpisodes: [download("Downloaded Episode", podcast: "Example Podcast")],
            remainingNewEpisodes: [],
            issues: []
        )

        #expect(summary.text == "Example Podcast · 1 downloaded")
    }

    @Test
    func downloadedEpisodeDetailsMergeWithoutDuplicates() {
        let first = download("First", podcast: "Podcast A")
        let second = download("Second", podcast: "Podcast B")

        let merged = PodcastRefreshEpisodeDetail.merging(
            [first],
            with: [first, second]
        )

        #expect(merged == [first, second])
    }

    @Test
    func successfulManualDownloadMovesEpisodeFromStillNewToDownloaded() {
        let downloadedEpisode = download("Grainy", podcast: "Cabinet of Curiosities")
        let remainingEpisode = download("Another Episode", podcast: "Cabinet of Curiosities")
        var summary = PodcastRefreshSummary(
            scope: .allPodcasts,
            checkedPodcastCount: 4,
            discoveredEpisodeCount: 2,
            downloadedEpisodes: [],
            remainingNewEpisodes: [downloadedEpisode, remainingEpisode],
            issues: []
        )

        summary.recordDownloadedEpisodes([downloadedEpisode])

        #expect(summary.text == "4 checked · 2 episodes found · 1 still new · 1 downloaded")
        #expect(summary.downloadedEpisodes == [downloadedEpisode])
        #expect(summary.remainingNewEpisodes == [remainingEpisode])
    }

    @Test
    func noChangesSummaryConfirmsRefreshCompleted() {
        let summary = PodcastRefreshSummary(
            scope: .allPodcasts,
            checkedPodcastCount: 120,
            discoveredEpisodeCount: 0,
            downloadedEpisodes: [],
            remainingNewEpisodes: [],
            issues: []
        )

        #expect(summary.text == "120 checked · No episodes found")
        #expect(!summary.hasDetails)
    }

    @Test
    func individualPodcastSummaryNamesPodcastAndReportsFailures() {
        let summary = PodcastRefreshSummary(
            scope: .podcast("Example Podcast"),
            checkedPodcastCount: 1,
            discoveredEpisodeCount: 1,
            downloadedEpisodes: [],
            remainingNewEpisodes: [download("New Episode", podcast: "Example Podcast")],
            issues: [PodcastRefreshIssue(
                id: "failure",
                title: "Podcast refresh failed",
                podcastTitle: "Example Podcast",
                message: "Network unavailable"
            )]
        )

        #expect(summary.text == "Example Podcast · 1 episode found · 1 still new · 1 needs attention")
        #expect(summary.parts.map(\.tone) == [.neutral, .discovery, .newEpisodes, .warning])
    }

    @Test
    func carriedOverNewEpisodesRemainVisibleWhenRefreshFindsNothing() {
        let summary = PodcastRefreshSummary(
            scope: .allPodcasts,
            checkedPodcastCount: 120,
            discoveredEpisodeCount: 0,
            downloadedEpisodes: [],
            remainingNewEpisodes: [download("Still New", podcast: "Example Podcast")],
            issues: []
        )

        #expect(summary.text == "120 checked · No episodes found · 1 still new")
        #expect(summary.parts.last?.tone == .newEpisodes)
    }

    @Test
    func allPodcastProgressIncludesCompletedAndTotalCounts() {
        let scope = PodcastRefreshDisplayScope.allPodcasts
        #expect(scope.progressText(PodcastRefreshProgress(completedCount: 34, totalCount: 120)) ==
            "Checking podcasts… 34 of 120")
    }

    private func download(_ title: String, podcast: String) -> PodcastRefreshEpisodeDetail {
        PodcastRefreshEpisodeDetail(Episode(
            id: title,
            subscriptionID: UUID(),
            podcastTitle: podcast,
            title: title,
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        ))
    }
}
