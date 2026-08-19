import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SQLiteEpisodeStoreTests {
    @Test
    func savesLoadsAndMergesEpisodeState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let first = fixture.records(number: 1)
        let second = fixture.records(number: 2)
        try fixture.store.savePreparedEpisodes([first.prepared])
        try fixture.store.saveDownloadedEpisodes([first.downloaded])
        try fixture.store.saveRemovedEpisodes([first.removed])

        try fixture.store.mergePreparedEpisodes([second.prepared])
        try fixture.store.mergeDownloadedEpisodes([second.downloaded])
        try fixture.store.mergeRemovedEpisodes([second.removed])

        #expect(Set(try fixture.store.loadPreparedEpisodes().map(\.persistenceKey)) == [
            first.prepared.persistenceKey,
            second.prepared.persistenceKey,
        ])
        #expect(Set(try fixture.store.loadDownloadedEpisodes().map(\.id)) == [
            first.downloaded.id,
            second.downloaded.id,
        ])
        #expect(Set(try fixture.store.loadRemovedEpisodes().map(\.id)) == [
            first.removed.id,
            second.removed.id,
        ])
    }

    @Test
    func importsLegacyJSONOnceAndKeepsSourceFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.records(number: 1)

        try JSONPreparedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "prepared-episodes.json")
        ).savePreparedEpisodes([original.prepared])
        try JSONDownloadedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "downloaded-episodes.json")
        ).saveDownloadedEpisodes([original.downloaded])
        try JSONRemovedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "removed-episodes.json")
        ).saveRemovedEpisodes([original.removed])

        #expect(try fixture.store.loadDownloadedEpisodes() == [original.downloaded])
        #expect(FileManager.default.fileExists(atPath: fixture.supportURL.appending(path: "downloaded-episodes.json").path))

        let stale = fixture.records(number: 2)
        try JSONDownloadedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "downloaded-episodes.json")
        ).saveDownloadedEpisodes([stale.downloaded])
        let reopenedStore = SQLiteEpisodeStore(
            fileURL: fixture.databaseURL,
            supportDirectoryURL: fixture.supportURL
        )
        #expect(try reopenedStore.loadDownloadedEpisodes() == [original.downloaded])
    }

    @Test
    func corruptLegacyJSONDoesNotPartiallyImportAndCanRetryAfterRepair() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let records = fixture.records(number: 1)

        try JSONPreparedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "prepared-episodes.json")
        ).savePreparedEpisodes([records.prepared])
        try Data("invalid".utf8).write(
            to: fixture.supportURL.appending(path: "downloaded-episodes.json"),
            options: .atomic
        )

        #expect(throws: (any Error).self) {
            try fixture.store.loadPreparedEpisodes()
        }

        try JSONDownloadedEpisodeStore(
            fileURL: fixture.supportURL.appending(path: "downloaded-episodes.json")
        ).saveDownloadedEpisodes([records.downloaded])
        let retryingStore = SQLiteEpisodeStore(
            fileURL: fixture.databaseURL,
            supportDirectoryURL: fixture.supportURL
        )
        #expect(try retryingStore.loadPreparedEpisodes() == [records.prepared])
        #expect(try retryingStore.loadDownloadedEpisodes() == [records.downloaded])
    }

    @Test
    func corruptDatabaseDoesNotRemoveLegacyRecoveryFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let records = fixture.records(number: 1)
        let legacyURL = fixture.supportURL.appending(path: "downloaded-episodes.json")
        try FileManager.default.createDirectory(at: fixture.supportURL, withIntermediateDirectories: true)
        try JSONDownloadedEpisodeStore(fileURL: legacyURL).saveDownloadedEpisodes([records.downloaded])
        try Data("not a sqlite database".utf8).write(to: fixture.databaseURL, options: .atomic)

        #expect(throws: (any Error).self) {
            try fixture.store.loadDownloadedEpisodes()
        }
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try JSONDownloadedEpisodeStore(fileURL: legacyURL).loadDownloadedEpisodes() == [records.downloaded])
    }

    @Test
    func handlesLargeDownloadHistoryWithoutReplacingExistingRows() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let records = (0..<20_000).map { fixture.records(number: $0).downloaded }
        try fixture.store.saveDownloadedEpisodes(records)
        let replacement = DownloadedEpisodeRecord(
            subscriptionID: fixture.subscriptionID,
            episodeID: "episode-19999",
            episodeTitle: "Updated title",
            preparationAction: .convertedToMP3,
            downloadedAt: Date(timeIntervalSince1970: 30_000)
        )
        try fixture.store.mergeDownloadedEpisodes([replacement])

        let loaded = try fixture.store.loadDownloadedEpisodes()
        #expect(loaded.count == 20_000)
        #expect(loaded.first(where: { $0.episodeID == "episode-19999" }) == replacement)
    }
}

private struct Fixture {
    let rootURL: URL
    let supportURL: URL
    let databaseURL: URL
    let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let store: SQLiteEpisodeStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        supportURL = rootURL.appending(path: "Support", directoryHint: .isDirectory)
        databaseURL = supportURL.appending(path: "episodes.sqlite3", directoryHint: .notDirectory)
        store = SQLiteEpisodeStore(fileURL: databaseURL, supportDirectoryURL: supportURL)
    }

    func records(number: Int) -> (prepared: PreparedEpisode, downloaded: DownloadedEpisodeRecord, removed: RemovedEpisodeRecord) {
        let episode = Episode(
            id: "episode-\(number)",
            subscriptionID: subscriptionID,
            podcastTitle: "Example Podcast",
            title: "Episode \(number)",
            publicationDate: Date(timeIntervalSince1970: TimeInterval(number)),
            enclosureURL: URL(string: "https://example.com/episode-\(number).mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
        return (
            PreparedEpisode(
                episode: episode,
                sourceFileURL: supportURL.appending(path: "source-\(number).mp3"),
                preparedFileURL: supportURL.appending(path: "prepared-\(number).mp3"),
                preparationAction: .passthroughMP3,
                preparedAt: Date(timeIntervalSince1970: TimeInterval(number))
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
                publicationDate: episode.publicationDate,
                deviceName: "Test Player",
                removedAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
