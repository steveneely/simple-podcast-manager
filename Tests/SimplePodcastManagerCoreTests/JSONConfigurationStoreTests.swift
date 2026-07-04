import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct JSONConfigurationStoreTests {
    @Test
    func missingConfigurationReturnsDefaults() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        let store = JSONConfigurationStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        let configuration = try store.loadConfiguration()

        #expect(configuration == AppConfiguration())
    }

    @Test
    func savesAndLoadsConfigurationRoundTrip() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        let store = JSONConfigurationStore(fileURL: fileURL)
        let configuration = AppConfiguration(
            settings: AppSettings(
                ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg"
            ),
            feedSubscriptions: [
                FeedSubscription(
                    title: "Accidental Tech Podcast",
                    rssURL: URL(string: "https://atp.fm/rss")!
                )
            ]
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        try store.saveConfiguration(configuration)
        let loadedConfiguration = try store.loadConfiguration()

        #expect(loadedConfiguration == configuration)
    }

    @Test
    func loadsLegacySubscriptionsWithRetentionPolicy() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        let store = JSONConfigurationStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try """
        {
          "settings" : {},
          "feedSubscriptions" : [
            {
              "id" : "11111111-1111-1111-1111-111111111111",
              "title" : "Legacy Podcast",
              "rssURL" : "https://example.com/feed.xml",
              "retentionPolicy" : {
                "keepLatestEpisodes" : {
                  "_0" : 5
                }
              },
              "isEnabled" : true
            }
          ]
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try store.loadConfiguration()

        #expect(configuration.feedSubscriptions == [
            FeedSubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Legacy Podcast",
                rssURL: URL(string: "https://example.com/feed.xml")!
            )
        ])
    }
}
