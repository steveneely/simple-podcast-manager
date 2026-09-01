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
                allowsInsecureDownloads: true,
                prefixesPublicationDateInEpisodeTitles: true,
                mp3Genre: "Spoken Word",
                automaticDownloadLimit: .latest3,
                deviceCleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 10),
                inactivePodcastThreshold: .oneYear
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
    func preservesBlankMP3GenreAsExplicitOptOut() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        let store = JSONConfigurationStore(fileURL: fileURL)
        let configuration = AppConfiguration(settings: AppSettings(mp3Genre: ""))

        try store.saveConfiguration(configuration)

        #expect(try store.loadConfiguration().settings.mp3Genre.isEmpty)
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
        #expect(!configuration.settings.prefixesPublicationDateInEpisodeTitles)
        #expect(configuration.settings.mp3Genre == AppSettings.defaultMP3Genre)
        #expect(configuration.settings.automaticDownloadLimit == .off)
        #expect(configuration.settings.deviceCleanupPolicy == DeviceCleanupPolicy())
        #expect(configuration.settings.inactivePodcastThreshold == .sixMonths)
        #expect(configuration.feedSubscriptions.isEmpty)
    }

    @Test
    func ignoresLegacyAgeBasedCleanupAndDefaultsToOff() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        try #"""
        {
          "settings" : {
            "deviceCleanupPolicy" : {
              "isEnabled" : true,
              "episodeAgeDays" : 30
            }
          },
          "feedSubscriptions" : []
        }
        """#.data(using: .utf8)!.write(to: fileURL)

        let configuration = try JSONConfigurationStore(fileURL: fileURL).loadConfiguration()

        #expect(configuration.settings.deviceCleanupPolicy == DeviceCleanupPolicy())
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
        #expect(!configuration.settings.prefixesPublicationDateInEpisodeTitles)
        #expect(configuration.settings.mp3Genre == AppSettings.defaultMP3Genre)
        #expect(configuration.settings.automaticDownloadLimit == .off)
        #expect(configuration.settings.deviceCleanupPolicy == DeviceCleanupPolicy())
        #expect(configuration.settings.inactivePodcastThreshold == .sixMonths)
    }

    @Test
    func loadsLegacyFeedAsIncludedInAutomaticDownloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"""
        {
          "settings" : {},
          "feedSubscriptions" : [{
            "id" : "00000000-0000-0000-0000-000000000001",
            "title" : "Example",
            "rssURL" : "https:\/\/example.com\/feed.xml",
            "isEnabled" : true
          }]
        }
        """#.data(using: .utf8)!.write(to: fileURL)

        let configuration = try JSONConfigurationStore(fileURL: fileURL).loadConfiguration()

        #expect(configuration.feedSubscriptions.first?.includesInAutomaticDownloads == true)
    }
}
