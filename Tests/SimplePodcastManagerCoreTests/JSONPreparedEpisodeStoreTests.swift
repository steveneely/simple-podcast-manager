import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONPreparedEpisodeStoreTests {
    @Test
    func savesAndLoadsPreparedEpisodesRoundTrip() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("prepared-episodes.json")
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        let preparedAt = Date(timeIntervalSince1970: 1_713_800_000)
        let preparedEpisodes = [
            PreparedEpisode(
                episode: Episode(
                    id: "ep-1",
                    podcastTitle: "Example Podcast",
                    title: "Episode 1",
                    enclosureURL: URL(string: "https://example.com/episode.mp3")!,
                    sourceFeedURL: URL(string: "https://example.com/feed.xml")!
                ),
                sourceFileURL: URL(fileURLWithPath: "/tmp/episode.mp3"),
                preparedFileURL: URL(fileURLWithPath: "/tmp/episode.mp3"),
                preparationAction: .passthroughMP3,
                preparedAt: preparedAt
            )
        ]
        let store = JSONPreparedEpisodeStore(fileURL: fileURL)

        try store.savePreparedEpisodes(preparedEpisodes)

        #expect(try store.loadPreparedEpisodes() == preparedEpisodes)
    }
}
