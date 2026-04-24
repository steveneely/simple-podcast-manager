import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct AppDataBackupServiceTests {
    @Test
    func exportBackupCopiesKnownAppDataAndWritesManifest() throws {
        let testRootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let supportURL = testRootURL.appending(path: "Support", directoryHint: .isDirectory)
        let destinationURL = testRootURL.appending(path: "Backup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: testRootURL) }

        try writeSampleAppData(to: supportURL)
        let service = AppDataBackupService(supportDirectoryURL: supportURL)

        let backupURL = try service.exportBackup(
            to: destinationURL,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(backupURL.pathExtension == AppDataBackupService.backupPathExtension)
        #expect(FileManager.default.fileExists(atPath: backupURL.appending(path: "config.json").path))
        #expect(FileManager.default.fileExists(atPath: backupURL.appending(path: "prepared-episodes.json").path))
        #expect(FileManager.default.fileExists(atPath: backupURL.appending(path: "removed-episodes.json").path))

        let manifestData = try Data(contentsOf: backupURL.appending(path: "manifest.json"))
        let manifest = try JSONDecoder.iso8601Decoder.decode(AppDataBackupManifest.self, from: manifestData)
        #expect(manifest.appName == AppIdentity.displayName)
        #expect(manifest.formatVersion == 1)
        #expect(manifest.files == ["config.json", "prepared-episodes.json", "removed-episodes.json"])
    }

    @Test
    func importBackupValidatesAndRestoresKnownAppData() throws {
        let testRootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceSupportURL = testRootURL.appending(path: "SourceSupport", directoryHint: .isDirectory)
        let destinationSupportURL = testRootURL.appending(path: "DestinationSupport", directoryHint: .isDirectory)
        let backupDestinationURL = testRootURL.appending(path: "Backup.spmbackup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: testRootURL) }

        try writeSampleAppData(to: sourceSupportURL)
        try writeAlternateConfiguration(to: destinationSupportURL)

        let sourceService = AppDataBackupService(supportDirectoryURL: sourceSupportURL)
        let backupURL = try sourceService.exportBackup(to: backupDestinationURL)
        let destinationService = AppDataBackupService(supportDirectoryURL: destinationSupportURL)

        let previousBackupURL = try destinationService.importBackup(
            from: backupURL,
            importedAt: Date(timeIntervalSince1970: 60)
        )

        let restoredConfiguration = try JSONConfigurationStore(
            fileURL: destinationSupportURL.appending(path: "config.json")
        ).loadConfiguration()
        #expect(restoredConfiguration.feedSubscriptions.map(\.title) == ["Example Podcast"])
        #expect(previousBackupURL != nil)
        #expect(FileManager.default.fileExists(atPath: previousBackupURL!.appending(path: "config.json").path))
    }

    @Test
    func importBackupRejectsUnknownManifestFiles() throws {
        let testRootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let supportURL = testRootURL.appending(path: "Support", directoryHint: .isDirectory)
        let backupURL = testRootURL.appending(path: "BadBackup.spmbackup", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: testRootURL) }

        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let manifest = AppDataBackupManifest(
            appName: AppIdentity.displayName,
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 0),
            files: ["config.json", "../secret.txt"]
        )
        try JSONEncoder.iso8601Encoder.encode(manifest).write(to: backupURL.appending(path: "manifest.json"))
        try Data("{}".utf8).write(to: backupURL.appending(path: "config.json"))

        let service = AppDataBackupService(supportDirectoryURL: supportURL)

        #expect(throws: AppDataBackupError.unknownFiles(["../secret.txt"])) {
            try service.importBackup(from: backupURL)
        }
    }

    private func writeSampleAppData(to supportURL: URL) throws {
        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let episode = Episode(
            id: "episode-1",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode 1",
            publicationDate: Date(timeIntervalSince1970: 0),
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        try JSONConfigurationStore(fileURL: supportURL.appending(path: "config.json")).saveConfiguration(
            AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        id: subscriptionID,
                        title: "Example Podcast",
                        rssURL: URL(string: "https://example.com/feed.xml")!,
                        retentionPolicy: .keepLatestEpisodes(3)
                    )
                ]
            )
        )
        try JSONPreparedEpisodeStore(fileURL: supportURL.appending(path: "prepared-episodes.json")).savePreparedEpisodes([
            PreparedEpisode(
                episode: episode,
                sourceFileURL: supportURL.appending(path: "episode.mp3"),
                preparedFileURL: supportURL.appending(path: "episode.mp3"),
                preparationAction: .passthroughMP3
            )
        ])
        try JSONRemovedEpisodeStore(fileURL: supportURL.appending(path: "removed-episodes.json")).saveRemovedEpisodes([
            RemovedEpisodeRecord(
                subscriptionID: subscriptionID,
                episodeID: "episode-0",
                fileStem: "2026-01-01 Old Episode",
                episodeTitle: "Old Episode",
                publicationDate: Date(timeIntervalSince1970: 0),
                deviceName: "Walkman",
                removedAt: Date(timeIntervalSince1970: 1)
            )
        ])
    }

    private func writeAlternateConfiguration(to supportURL: URL) throws {
        try JSONConfigurationStore(fileURL: supportURL.appending(path: "config.json")).saveConfiguration(
            AppConfiguration(
                feedSubscriptions: [
                    FeedSubscription(
                        title: "Other Podcast",
                        rssURL: URL(string: "https://example.com/other.xml")!,
                        retentionPolicy: .keepLatestEpisodes(1)
                    )
                ]
            )
        )
    }
}

private extension JSONEncoder {
    static var iso8601Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
