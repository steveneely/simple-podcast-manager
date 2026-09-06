import Foundation
import XCTest
@testable import SimplePodcastManagerCore

final class SQLiteEpisodeStorePerformanceTests: XCTestCase {
    private var rootURL: URL!
    private var supportURL: URL!
    private var store: SQLiteEpisodeStore!
    private let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SPM_RUN_PERFORMANCE_TESTS"] == "1" else {
            throw XCTSkip("Set SPM_RUN_PERFORMANCE_TESTS=1 to run SQLite store scale and performance tests.")
        }
        rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        supportURL = rootURL.appending(path: "Support", directoryHint: .isDirectory)
        store = SQLiteEpisodeStore(
            fileURL: supportURL.appending(path: "episodes.sqlite3"),
            supportDirectoryURL: supportURL
        )
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        store = nil
        supportURL = nil
        rootURL = nil
    }

    func testUnifiedStartupSnapshotRead() throws {
        let records = (0..<2_000).map { number -> (PreparedEpisode, DownloadedEpisodeRecord, RemovedEpisodeRecord) in
            let episode = Episode(
                id: "episode-\(number)",
                subscriptionID: subscriptionID,
                podcastTitle: "Performance Podcast",
                title: "Episode \(number)",
                enclosureURL: URL(string: "https://example.com/episode-\(number).mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            )
            return (
                PreparedEpisode(
                    episode: episode,
                    sourceFileURL: supportURL.appending(path: "source-\(number).mp3"),
                    preparedFileURL: supportURL.appending(path: "prepared-\(number).mp3"),
                    preparationAction: .passthroughMP3
                ),
                DownloadedEpisodeRecord(
                    subscriptionID: subscriptionID,
                    episodeID: episode.id,
                    episodeTitle: episode.title,
                    preparationAction: .passthroughMP3,
                    downloadedAt: Date(timeIntervalSince1970: TimeInterval(number))
                ),
                RemovedEpisodeRecord(
                    subscriptionID: subscriptionID,
                    episodeID: episode.id,
                    fileStem: "Episode-\(number)",
                    episodeTitle: episode.title,
                    publicationDate: nil,
                    deviceName: "Test Player",
                    removedAt: Date(timeIntervalSince1970: TimeInterval(number))
                )
            )
        }
        try store.savePreparedEpisodes(records.map { $0.0 })
        try store.saveDownloadedEpisodes(records.map { $0.1 })
        try store.saveRemovedEpisodes(records.map { $0.2 })
        measure(metrics: [XCTClockMetric()]) {
            _ = try! store.loadStartupSnapshot()
        }
    }

    func testLargeAutomaticDownloadStateRoundTrip() throws {
        let podcasts = (0..<40).map { podcastNumber in
            AutomaticDownloadPodcastState(
                subscriptionID: UUID(
                    uuidString: String(format: "00000000-0000-0000-0000-%012d", podcastNumber + 1)
                )!,
                rssURL: URL(string: "https://example.com/feed-\(podcastNumber).xml")!,
                observedEpisodeIDs: (0..<400).map { "podcast-\(podcastNumber)-episode-\($0)" },
                pendingEpisodeIDs: ["podcast-\(podcastNumber)-episode-0"]
            )
        }
        let state = AutomaticDownloadState(podcasts: podcasts)
        try store.saveState(state)

        let loaded = try store.loadState()
        XCTAssertEqual(loaded.podcasts.count, 40)
        XCTAssertEqual(loaded.podcasts.reduce(0) { $0 + $1.observedEpisodeIDs.count }, 16_000)

        var updated = loaded
        updated.podcasts[0].pendingEpisodeIDs.removeAll()
        try store.saveState(updated)
        XCTAssertEqual(try store.loadState(), updated)
    }

    func testLargeDownloadHistoryMergePreservesExistingRows() throws {
        let records = (0..<20_000).map { number in
            DownloadedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: "episode-\(number)",
                episodeTitle: "Episode \(number)",
                preparationAction: .passthroughMP3,
                downloadedAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }
        try store.saveDownloadedEpisodes(records)
        let replacement = DownloadedEpisodeRecord(
            subscriptionID: subscriptionID,
            episodeID: "episode-19999",
            episodeTitle: "Updated title",
            preparationAction: .convertedToMP3,
            downloadedAt: Date(timeIntervalSince1970: 30_000)
        )
        try store.mergeDownloadedEpisodes([replacement])

        let loaded = try store.loadDownloadedEpisodes()
        XCTAssertEqual(loaded.count, 20_000)
        XCTAssertEqual(loaded.first(where: { $0.episodeID == "episode-19999" }), replacement)
    }
}
