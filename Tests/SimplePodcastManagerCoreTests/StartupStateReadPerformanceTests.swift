import Foundation
import XCTest
@testable import SimplePodcastManagerCore

final class StartupStateReadPerformanceTests: XCTestCase {
    private var rootURL: URL!
    private var store: SQLiteEpisodeStore!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SPM_RUN_PERFORMANCE_TESTS"] == "1" else {
            throw XCTSkip("Set SPM_RUN_PERFORMANCE_TESTS=1 to run startup performance benchmarks.")
        }
        rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let supportURL = rootURL.appending(path: "Support", directoryHint: .isDirectory)
        store = SQLiteEpisodeStore(
            fileURL: supportURL.appending(path: "episodes.sqlite3"),
            supportDirectoryURL: supportURL
        )

        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
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
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        store = nil
        rootURL = nil
    }

    func testUnifiedStartupSnapshotRead() {
        measure(metrics: [XCTClockMetric()]) {
            _ = try! store.loadStartupSnapshot()
        }
    }

    func testPreviousSeparateStartupReads() {
        measure(metrics: [XCTClockMetric()]) {
            _ = try! store.loadPreparedEpisodes()
            _ = try! store.loadDownloadedEpisodes()
            _ = try! store.loadRemovedEpisodes()
            _ = try! store.loadState()
            _ = try! store.loadFeedActivityState()
        }
    }
}
