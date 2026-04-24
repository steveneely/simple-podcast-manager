import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONPreparedEpisodeStoreTests {
    @Test
    func loadsLegacyPreparedEpisodesWithoutPreparedDate() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("prepared-episodes.json")
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try Data(
            """
            [
              {
                "episode" : {
                  "id" : "ep-1",
                  "podcastTitle" : "Example Podcast",
                  "title" : "Episode 1",
                  "enclosureURL" : "https:\\/\\/example.com\\/episode.mp3",
                  "sourceFeedURL" : "https:\\/\\/example.com\\/feed.xml"
                },
                "sourceFileURL" : "file:\\/\\/\\/tmp\\/episode.mp3",
                "preparedFileURL" : "file:\\/\\/\\/tmp\\/episode.mp3",
                "preparationAction" : "passthroughMP3"
              }
            ]
            """.utf8
        ).write(to: fileURL)

        let store = JSONPreparedEpisodeStore(fileURL: fileURL)
        let preparedEpisodes = try store.loadPreparedEpisodes()

        #expect(preparedEpisodes.count == 1)
        #expect(preparedEpisodes.first?.preparedAt == nil)
    }
}
