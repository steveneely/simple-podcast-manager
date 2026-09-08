import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SQLiteEpisodeStoreTests {
    @Test
    func savesAndLoadsPodcastPlaylistLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let episode = fixture.records(number: 1).prepared.episode
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        let playlist = try PodcastPlaylist(name: "Commute", entries: [entry])
        let library = PodcastPlaylistLibrary(
            playlists: [playlist],
            deviceStates: [
                "device": PodcastPlaylistDeviceState(ownedDeviceFileNames: ["Commute.m3u"])
            ]
        )

        try fixture.store.savePodcastPlaylistLibrary(library)

        #expect(try fixture.store.loadPodcastPlaylistLibrary() == library)
    }

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
    func startupSnapshotLoadsAllPersistedStateInOneRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let records = fixture.records(number: 1)
        let automaticDownloadState = AutomaticDownloadState(podcasts: [
            AutomaticDownloadPodcastState(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: [records.downloaded.episodeID],
                pendingEpisodeIDs: [records.downloaded.episodeID]
            )
        ])
        let podcastActivityState = PodcastActivityState(podcasts: [
            PodcastActivityEntry(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: [records.downloaded.episodeID],
                newEpisodeIDs: [records.downloaded.episodeID],
                newestPublicationDate: Date(timeIntervalSince1970: 1)
            )
        ])
        try fixture.store.savePreparedEpisodes([records.prepared])
        try fixture.store.saveDownloadedEpisodes([records.downloaded])
        try fixture.store.saveRemovedEpisodes([records.removed])
        try fixture.store.saveState(automaticDownloadState)
        try fixture.store.savePodcastActivityState(podcastActivityState)

        let snapshot = try fixture.store.loadStartupSnapshot()

        #expect(snapshot.preparedEpisodes == [records.prepared])
        #expect(snapshot.downloadedEpisodes == [records.downloaded])
        #expect(snapshot.removedEpisodes == [records.removed])
        #expect(snapshot.automaticDownloadState == automaticDownloadState)
        #expect(snapshot.podcastActivityState == podcastActivityState)
    }

    @Test
    func importsLegacyJSONOnceAndKeepsSourceFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.records(number: 1)

        try AppJSONFile.save(
            [original.prepared],
            to: fixture.supportURL.appending(path: "prepared-episodes.json")
        )
        try AppJSONFile.save(
            [original.downloaded],
            to: fixture.supportURL.appending(path: "downloaded-episodes.json")
        )
        try AppJSONFile.save(
            [original.removed],
            to: fixture.supportURL.appending(path: "removed-episodes.json")
        )

        #expect(try fixture.store.loadDownloadedEpisodes() == [original.downloaded])
        #expect(FileManager.default.fileExists(atPath: fixture.supportURL.appending(path: "downloaded-episodes.json").path))

        let stale = fixture.records(number: 2)
        try AppJSONFile.save(
            [stale.downloaded],
            to: fixture.supportURL.appending(path: "downloaded-episodes.json")
        )
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

        try AppJSONFile.save(
            [records.prepared],
            to: fixture.supportURL.appending(path: "prepared-episodes.json")
        )
        try Data("invalid".utf8).write(
            to: fixture.supportURL.appending(path: "downloaded-episodes.json"),
            options: .atomic
        )

        #expect(throws: (any Error).self) {
            try fixture.store.loadPreparedEpisodes()
        }

        try AppJSONFile.save(
            [records.downloaded],
            to: fixture.supportURL.appending(path: "downloaded-episodes.json")
        )
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
        try AppJSONFile.save([records.downloaded], to: legacyURL)
        try Data("not a sqlite database".utf8).write(to: fixture.databaseURL, options: .atomic)

        #expect(throws: (any Error).self) {
            try fixture.store.loadDownloadedEpisodes()
        }
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try AppJSONFile.load(
            [DownloadedEpisodeRecord].self,
            from: legacyURL,
            defaultValue: []
        ) == [records.downloaded])
    }

    @Test
    func savesLoadsAndReplacesAutomaticDownloadState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstState = AutomaticDownloadState(podcasts: [
            AutomaticDownloadPodcastState(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: ["newest", "older"],
                pendingEpisodeIDs: ["newest"]
            )
        ])
        try fixture.store.saveState(firstState)

        #expect(try fixture.store.loadState() == firstState)

        let replacementState = AutomaticDownloadState(podcasts: [
            AutomaticDownloadPodcastState(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: ["latest", "newest", "older"],
                pendingEpisodeIDs: ["latest"]
            )
        ])
        try fixture.store.saveState(replacementState)

        #expect(try fixture.store.loadState() == replacementState)
        try fixture.store.saveState(AutomaticDownloadState())
        #expect(try fixture.store.loadState().podcasts.isEmpty)
    }

    @Test
    func savesLoadsAndReplacesPodcastActivityState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = PodcastActivityState(podcasts: [
            PodcastActivityEntry(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: ["newest", "older"],
                newEpisodeIDs: ["newest"],
                newestPublicationDate: Date(timeIntervalSince1970: 100)
            )
        ])

        try fixture.store.savePodcastActivityState(state)
        #expect(try fixture.store.loadPodcastActivityState() == state)

        try fixture.store.savePodcastActivityState(PodcastActivityState())
        #expect(try fixture.store.loadPodcastActivityState().podcasts.isEmpty)
    }

    @Test
    func correctsTwoDigitPublicationYearInPersistedPodcastActivity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parsedAsYear26 = try #require(calendar.date(from: DateComponents(year: 26, month: 9, day: 1)))
        let state = PodcastActivityState(podcasts: [
            PodcastActivityEntry(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                newestPublicationDate: parsedAsYear26
            )
        ])
        try fixture.store.savePodcastActivityState(state)

        let loadedDate = try #require(fixture.store.loadPodcastActivityState().podcasts.first?.newestPublicationDate)

        #expect(calendar.component(.year, from: loadedDate) == 2026)
    }

    @Test
    func importsLegacyAutomaticDownloadStateOnceAndKeepsSourceFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacyURL = fixture.supportURL.appending(path: "automatic-downloads.json")
        let original = AutomaticDownloadState(podcasts: [
            AutomaticDownloadPodcastState(
                subscriptionID: fixture.subscriptionID,
                rssURL: URL(string: "https://example.com/feed.xml")!,
                observedEpisodeIDs: ["episode-2", "episode-1"],
                pendingEpisodeIDs: ["episode-2"]
            )
        ])
        try AppJSONFile.save(original, to: legacyURL)

        #expect(try fixture.store.loadState() == original)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))

        try AppJSONFile.save(AutomaticDownloadState(), to: legacyURL)
        let reopenedStore = SQLiteEpisodeStore(
            fileURL: fixture.databaseURL,
            supportDirectoryURL: fixture.supportURL
        )
        #expect(try reopenedStore.loadState() == original)
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
