import Foundation
import Testing
@testable import PodcastSwiftCore

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
                ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg",
                dryRunByDefault: false,
                ejectAfterSyncByDefault: true
            ),
            feedSubscriptions: [
                FeedSubscription(
                    title: "Accidental Tech Podcast",
                    rssURL: URL(string: "https://atp.fm/rss")!,
                    retentionPolicy: .keepLatestEpisodes(5)
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
}
