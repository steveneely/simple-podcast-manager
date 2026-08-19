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
                ffmpegExecutablePath: "/opt/homebrew/bin/ffmpeg",
                allowsInsecureDownloads: true
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
    func loadsLegacySettingsWithoutAppearancePreference() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        let store = JSONConfigurationStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try #"""
        {
          "settings" : {
            "ffmpegExecutablePath" : "/opt/homebrew/bin/ffmpeg"
          },
          "feedSubscriptions" : []
        }
        """#.data(using: .utf8)!.write(to: fileURL)

        let configuration = try store.loadConfiguration()

        #expect(configuration.settings.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(configuration.settings.appearancePreference == .system)
        #expect(!configuration.settings.allowsInsecureDownloads)
    }

    @Test
    func migratesLegacyInsecureEpisodeDownloadPreference() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        let store = JSONConfigurationStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try #"""
        {
          "settings" : {
            "appearancePreference" : "system",
            "allowsInsecureEpisodeDownloads" : true
          },
          "feedSubscriptions" : []
        }
        """#.data(using: .utf8)!.write(to: fileURL)

        let configuration = try store.loadConfiguration()

        #expect(configuration.settings.allowsInsecureDownloads)
    }
}
