import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONRemovedEpisodeStoreTests {
    @Test
    func savesAndLoadsRemovedEpisodesRoundTrip() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("removed-episodes.json")
        let store = JSONRemovedEpisodeStore(fileURL: fileURL)
        let records = [
            RemovedEpisodeRecord(
                subscriptionID: UUID(uuidString: "A28B8431-E287-4A5A-9C28-D83E552248E4")!,
                episodeID: "ep-1",
                fileStem: "2024.04.21-Episode 1-(Example Podcast)",
                episodeTitle: "Episode 1",
                publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                deviceName: "WALKMAN",
                removedAt: Date(timeIntervalSince1970: 1_713_800_000)
            )
        ]

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        try store.saveRemovedEpisodes(records)
        let loadedRecords = try store.loadRemovedEpisodes()

        #expect(loadedRecords == records)
    }
}
