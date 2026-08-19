import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONAutomaticDownloadStateStoreTests {
    @Test
    func missingFileReturnsEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = try JSONAutomaticDownloadStateStore(
            fileURL: directory.appendingPathComponent("automatic-downloads.json")
        ).loadState()

        #expect(state == AutomaticDownloadState())
    }

    @Test
    func savesAndLoadsState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONAutomaticDownloadStateStore(
            fileURL: directory.appendingPathComponent("automatic-downloads.json")
        )
        let state = AutomaticDownloadState(feeds: [
            AutomaticDownloadFeedState(
                subscriptionID: UUID(),
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: ["one", "two"],
                pendingEpisodeIDs: ["two"]
            )
        ])

        try store.saveState(state)

        #expect(try store.loadState() == state)
    }
}
