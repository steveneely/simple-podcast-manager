import Foundation
import GRDB

public final class SQLiteEpisodeStore: PreparedEpisodeStore, DownloadedEpisodeStore, RemovedEpisodeStore, AutomaticDownloadStateStore, PodcastActivityStateStore, EpisodeStateStartupLoading, @unchecked Sendable {
    public static let shared = SQLiteEpisodeStore()

    public let fileURL: URL

    private let supportDirectoryURL: URL
    private let fileManager: FileManager
    private let databaseLock = NSLock()
    private var databaseResult: Result<DatabaseQueue, Error>?

    public init(
        fileURL: URL = SQLiteEpisodeStore.defaultFileURL(),
        supportDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.supportDirectoryURL = supportDirectoryURL ?? fileURL.deletingLastPathComponent()
        self.fileManager = fileManager
    }

    public func loadPreparedEpisodes() throws -> [PreparedEpisode] {
        try loadRecords(PreparedEpisode.self, from: .prepared)
    }

    public func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        try replaceRecords(in: .prepared, with: try preparedEpisodes.map(Self.preparedRow))
    }

    public func mergePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        try mergeRows(try preparedEpisodes.map(Self.preparedRow), into: .prepared)
    }

    public func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord] {
        try loadRecords(DownloadedEpisodeRecord.self, from: .downloaded)
    }

    public func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        try replaceRecords(in: .downloaded, with: try downloadedEpisodes.map(Self.downloadedRow))
    }

    public func mergeDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        try mergeRows(try downloadedEpisodes.map(Self.downloadedRow), into: .downloaded)
    }

    public func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord] {
        try loadRecords(RemovedEpisodeRecord.self, from: .removed)
    }

    public func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        try replaceRecords(in: .removed, with: try removedEpisodes.map(Self.removedRow))
    }

    public func mergeRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        try mergeRows(try removedEpisodes.map(Self.removedRow), into: .removed)
    }

    public func loadState() throws -> AutomaticDownloadState {
        let queue = try databaseQueue()
        return try queue.read(Self.loadAutomaticDownloadState)
    }

    public func saveState(_ state: AutomaticDownloadState) throws {
        let queue = try databaseQueue()
        try queue.write { database in
            try Self.saveAutomaticDownloadState(state, database: database)
        }
    }

    public func loadPodcastActivityState() throws -> PodcastActivityState {
        let queue = try databaseQueue()
        return try queue.read(Self.loadPodcastActivityState)
    }

    public func loadStartupSnapshot() throws -> EpisodeStateStartupSnapshot {
        let queue = try databaseQueue()
        return try queue.read { database in
            try EpisodeStateStartupSnapshot(
                preparedEpisodes: Self.loadRecords(PreparedEpisode.self, from: .prepared, database: database),
                downloadedEpisodes: Self.loadRecords(DownloadedEpisodeRecord.self, from: .downloaded, database: database),
                removedEpisodes: Self.loadRecords(RemovedEpisodeRecord.self, from: .removed, database: database),
                automaticDownloadState: Self.loadAutomaticDownloadState(database: database),
                podcastActivityState: Self.loadPodcastActivityState(database: database)
            )
        }
    }

    public func savePodcastActivityState(_ state: PodcastActivityState) throws {
        let queue = try databaseQueue()
        try queue.write { database in
            try Self.savePodcastActivityState(state, database: database)
        }
    }

    func loadAllAppData() throws -> SQLiteAppData {
        let queue = try databaseQueue()
        return try queue.read { database in
            try SQLiteAppData(
                preparedEpisodes: Self.loadRecords(PreparedEpisode.self, from: .prepared, database: database),
                downloadedEpisodes: Self.loadRecords(DownloadedEpisodeRecord.self, from: .downloaded, database: database),
                removedEpisodes: Self.loadRecords(RemovedEpisodeRecord.self, from: .removed, database: database),
                automaticDownloadState: Self.loadAutomaticDownloadState(database: database),
                podcastActivityState: Self.loadPodcastActivityState(database: database)
            )
        }
    }

    public func replaceAllAppData(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord],
        automaticDownloadState: AutomaticDownloadState,
        podcastActivityState: PodcastActivityState
    ) throws {
        let queue = try databaseQueue()
        try queue.write { database in
            try Self.replaceRows(try preparedEpisodes.map(Self.preparedRow), in: .prepared, database: database)
            try Self.replaceRows(try downloadedEpisodes.map(Self.downloadedRow), in: .downloaded, database: database)
            try Self.replaceRows(try removedEpisodes.map(Self.removedRow), in: .removed, database: database)
            try Self.saveAutomaticDownloadState(automaticDownloadState, database: database)
            try Self.savePodcastActivityState(podcastActivityState, database: database)
        }
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "episodes.sqlite3", directoryHint: .notDirectory)
    }

    private func databaseQueue() throws -> DatabaseQueue {
        databaseLock.lock()
        defer { databaseLock.unlock() }

        if let databaseResult {
            return try databaseResult.get()
        }

        let result = Result { try makeDatabaseQueue() }
        databaseResult = result
        return try result.get()
    }

    private func makeDatabaseQueue() throws -> DatabaseQueue {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: fileURL.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("episode-state-v1") { database in
            try database.execute(sql: """
                CREATE TABLE preparedEpisodes (
                    recordKey TEXT PRIMARY KEY NOT NULL,
                    subscriptionID TEXT,
                    episodeID TEXT NOT NULL,
                    preparedAt DOUBLE NOT NULL,
                    recordJSON BLOB NOT NULL
                );
                CREATE INDEX preparedEpisodes_subscription_episode
                    ON preparedEpisodes(subscriptionID, episodeID);

                CREATE TABLE downloadedEpisodes (
                    recordKey TEXT PRIMARY KEY NOT NULL,
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT NOT NULL,
                    downloadedAt DOUBLE NOT NULL,
                    recordJSON BLOB NOT NULL
                );
                CREATE UNIQUE INDEX downloadedEpisodes_subscription_episode
                    ON downloadedEpisodes(subscriptionID, episodeID);

                CREATE TABLE removedEpisodes (
                    recordKey TEXT PRIMARY KEY NOT NULL,
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT,
                    removedAt DOUBLE NOT NULL,
                    recordJSON BLOB NOT NULL
                );
                CREATE INDEX removedEpisodes_subscription_episode
                    ON removedEpisodes(subscriptionID, episodeID);

                CREATE TABLE appMetadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                """)
        }
        migrator.registerMigration("automatic-download-state-v1") { database in
            try database.execute(sql: """
                CREATE TABLE automaticDownloadFeeds (
                    subscriptionID TEXT PRIMARY KEY NOT NULL,
                    rssURL TEXT NOT NULL
                );

                CREATE TABLE automaticDownloadObservedEpisodes (
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    PRIMARY KEY (subscriptionID, episodeID)
                );
                CREATE INDEX automaticDownloadObservedEpisodes_order
                    ON automaticDownloadObservedEpisodes(subscriptionID, position);

                CREATE TABLE automaticDownloadPendingEpisodes (
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT NOT NULL,
                    PRIMARY KEY (subscriptionID, episodeID)
                );
                """)
        }
        migrator.registerMigration("feed-activity-state-v1") { database in
            // The migration name and feedActivity table names are permanent
            // database identifiers retained for compatibility with existing installs.
            try database.execute(sql: """
                CREATE TABLE feedActivityFeeds (
                    subscriptionID TEXT PRIMARY KEY NOT NULL,
                    rssURL TEXT NOT NULL,
                    newestPublicationDate DOUBLE
                );

                CREATE TABLE feedActivityObservedEpisodes (
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    PRIMARY KEY (subscriptionID, episodeID)
                );
                CREATE INDEX feedActivityObservedEpisodes_order
                    ON feedActivityObservedEpisodes(subscriptionID, position);

                CREATE TABLE feedActivityNewEpisodes (
                    subscriptionID TEXT NOT NULL,
                    episodeID TEXT NOT NULL,
                    PRIMARY KEY (subscriptionID, episodeID)
                );
                """)
        }
        try migrator.migrate(queue)
        try importLegacyJSONIfNeeded(into: queue)
        try importLegacyAutomaticDownloadJSONIfNeeded(into: queue)
        return queue
    }

    private func importLegacyJSONIfNeeded(into queue: DatabaseQueue) throws {
        let hasImported = try queue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT value FROM appMetadata WHERE key = ?",
                arguments: [Self.legacyImportKey]
            ) == "complete"
        }
        guard !hasImported else { return }

        let preparedEpisodes = try AppJSONFile.load(
            [PreparedEpisode].self,
            from: supportDirectoryURL.appending(path: "prepared-episodes.json"),
            defaultValue: []
        )
        let downloadedEpisodes = try AppJSONFile.load(
            [DownloadedEpisodeRecord].self,
            from: supportDirectoryURL.appending(path: "downloaded-episodes.json"),
            defaultValue: []
        )
        let removedEpisodes = try AppJSONFile.load(
            [RemovedEpisodeRecord].self,
            from: supportDirectoryURL.appending(path: "removed-episodes.json"),
            defaultValue: []
        )

        try queue.write { database in
            try Self.replaceRows(try preparedEpisodes.map(Self.preparedRow), in: .prepared, database: database)
            try Self.replaceRows(try downloadedEpisodes.map(Self.downloadedRow), in: .downloaded, database: database)
            try Self.replaceRows(try removedEpisodes.map(Self.removedRow), in: .removed, database: database)
            try database.execute(
                sql: "INSERT INTO appMetadata (key, value) VALUES (?, ?)",
                arguments: [Self.legacyImportKey, "complete"]
            )
        }
    }

    private func importLegacyAutomaticDownloadJSONIfNeeded(into queue: DatabaseQueue) throws {
        let hasImported = try queue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT value FROM appMetadata WHERE key = ?",
                arguments: [Self.legacyAutomaticDownloadImportKey]
            ) == "complete"
        }
        guard !hasImported else { return }

        let state = try AppJSONFile.load(
            AutomaticDownloadState.self,
            from: supportDirectoryURL.appending(path: "automatic-downloads.json"),
            defaultValue: AutomaticDownloadState()
        )

        try queue.write { database in
            try Self.saveAutomaticDownloadState(state, database: database)
            try database.execute(
                sql: "INSERT INTO appMetadata (key, value) VALUES (?, ?)",
                arguments: [Self.legacyAutomaticDownloadImportKey, "complete"]
            )
        }
    }

    private static func loadAutomaticDownloadState(database: Database) throws -> AutomaticDownloadState {
        let podcastRows = try Row.fetchAll(
            database,
            sql: "SELECT subscriptionID, rssURL FROM automaticDownloadFeeds ORDER BY subscriptionID"
        )
        let observedRows = try Row.fetchAll(
            database,
            sql: """
                SELECT subscriptionID, episodeID
                FROM automaticDownloadObservedEpisodes
                ORDER BY subscriptionID, position
                """
        )
        let pendingRows = try Row.fetchAll(
            database,
            sql: """
                SELECT subscriptionID, episodeID
                FROM automaticDownloadPendingEpisodes
                ORDER BY subscriptionID, episodeID
                """
        )

        var observedEpisodeIDsBySubscription: [String: [String]] = [:]
        for row in observedRows {
            let subscriptionID: String = row["subscriptionID"]
            let episodeID: String = row["episodeID"]
            observedEpisodeIDsBySubscription[subscriptionID, default: []].append(episodeID)
        }

        var pendingEpisodeIDsBySubscription: [String: Set<String>] = [:]
        for row in pendingRows {
            let subscriptionID: String = row["subscriptionID"]
            let episodeID: String = row["episodeID"]
            pendingEpisodeIDsBySubscription[subscriptionID, default: []].insert(episodeID)
        }

        let podcasts = try podcastRows.map { row -> AutomaticDownloadPodcastState in
            let storedSubscriptionID: String = row["subscriptionID"]
            let storedRSSURL: String = row["rssURL"]
            guard let subscriptionID = UUID(uuidString: storedSubscriptionID) else {
                throw SQLiteAutomaticDownloadStateError.invalidSubscriptionID(storedSubscriptionID)
            }
            guard let rssURL = URL(string: storedRSSURL) else {
                throw SQLiteAutomaticDownloadStateError.invalidRSSURL(storedRSSURL)
            }
            return AutomaticDownloadPodcastState(
                subscriptionID: subscriptionID,
                rssURL: rssURL,
                observedEpisodeIDs: observedEpisodeIDsBySubscription[storedSubscriptionID] ?? [],
                pendingEpisodeIDs: pendingEpisodeIDsBySubscription[storedSubscriptionID] ?? []
            )
        }
        return AutomaticDownloadState(podcasts: podcasts)
    }

    private static func saveAutomaticDownloadState(
        _ state: AutomaticDownloadState,
        database: Database
    ) throws {
        let existingState = try loadAutomaticDownloadState(database: database)
        let existingPodcastsByID = Dictionary(uniqueKeysWithValues: existingState.podcasts.map { ($0.subscriptionID, $0) })
        var updatedPodcastsByID: [UUID: AutomaticDownloadPodcastState] = [:]
        for podcast in state.podcasts {
            updatedPodcastsByID[podcast.subscriptionID] = normalized(podcast)
        }

        for removedSubscriptionID in Set(existingPodcastsByID.keys).subtracting(updatedPodcastsByID.keys) {
            try deleteAutomaticDownloadPodcast(subscriptionID: removedSubscriptionID, database: database)
        }

        for podcast in updatedPodcastsByID.values where existingPodcastsByID[podcast.subscriptionID] != podcast {
            let subscriptionID = podcast.subscriptionID.uuidString.lowercased()
            try database.execute(
                sql: "DELETE FROM automaticDownloadObservedEpisodes WHERE subscriptionID = ?",
                arguments: [subscriptionID]
            )
            try database.execute(
                sql: "DELETE FROM automaticDownloadPendingEpisodes WHERE subscriptionID = ?",
                arguments: [subscriptionID]
            )
            try database.execute(
                sql: """
                    INSERT INTO automaticDownloadFeeds (subscriptionID, rssURL)
                    VALUES (?, ?)
                    ON CONFLICT(subscriptionID) DO UPDATE SET rssURL = excluded.rssURL
                    """,
                arguments: [subscriptionID, podcast.rssURL.absoluteString]
            )

            for (position, episodeID) in podcast.observedEpisodeIDs.enumerated() {
                try database.execute(
                    sql: """
                        INSERT INTO automaticDownloadObservedEpisodes (subscriptionID, episodeID, position)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [subscriptionID, episodeID, position]
                )
            }
            for episodeID in podcast.pendingEpisodeIDs.sorted() {
                try database.execute(
                    sql: """
                        INSERT INTO automaticDownloadPendingEpisodes (subscriptionID, episodeID)
                        VALUES (?, ?)
                        """,
                    arguments: [subscriptionID, episodeID]
                )
            }
        }
    }

    private static func deleteAutomaticDownloadPodcast(subscriptionID: UUID, database: Database) throws {
        let storedSubscriptionID = subscriptionID.uuidString.lowercased()
        try database.execute(
            sql: "DELETE FROM automaticDownloadObservedEpisodes WHERE subscriptionID = ?",
            arguments: [storedSubscriptionID]
        )
        try database.execute(
            sql: "DELETE FROM automaticDownloadPendingEpisodes WHERE subscriptionID = ?",
            arguments: [storedSubscriptionID]
        )
        try database.execute(
            sql: "DELETE FROM automaticDownloadFeeds WHERE subscriptionID = ?",
            arguments: [storedSubscriptionID]
        )
    }

    private static func normalized(_ podcast: AutomaticDownloadPodcastState) -> AutomaticDownloadPodcastState {
        var seenEpisodeIDs: Set<String> = []
        var normalizedPodcast = podcast
        normalizedPodcast.observedEpisodeIDs = podcast.observedEpisodeIDs.filter {
            seenEpisodeIDs.insert($0).inserted
        }
        return normalizedPodcast
    }

    private static func loadPodcastActivityState(database: Database) throws -> PodcastActivityState {
        let podcastRows = try Row.fetchAll(database, sql: "SELECT subscriptionID, rssURL, newestPublicationDate FROM feedActivityFeeds ORDER BY subscriptionID")
        let observedRows = try Row.fetchAll(database, sql: "SELECT subscriptionID, episodeID FROM feedActivityObservedEpisodes ORDER BY subscriptionID, position")
        let newRows = try Row.fetchAll(database, sql: "SELECT subscriptionID, episodeID FROM feedActivityNewEpisodes ORDER BY subscriptionID, episodeID")
        var observedBySubscription: [String: [String]] = [:]
        var newBySubscription: [String: Set<String>] = [:]
        for row in observedRows {
            observedBySubscription[row["subscriptionID"], default: []].append(row["episodeID"])
        }
        for row in newRows {
            newBySubscription[row["subscriptionID"], default: []].insert(row["episodeID"])
        }
        let podcasts = try podcastRows.map { row -> PodcastActivityEntry in
            let storedID: String = row["subscriptionID"]
            let storedURL: String = row["rssURL"]
            guard let subscriptionID = UUID(uuidString: storedID), let rssURL = URL(string: storedURL) else {
                throw SQLitePodcastActivityStateError.invalidPodcastEntry(storedID, storedURL)
            }
            let timestamp: Double? = row["newestPublicationDate"]
            return PodcastActivityEntry(
                subscriptionID: subscriptionID,
                rssURL: rssURL,
                observedEpisodeIDs: observedBySubscription[storedID] ?? [],
                newEpisodeIDs: newBySubscription[storedID] ?? [],
                newestPublicationDate: PublicationDateNormalizer.normalize(
                    timestamp.map(Date.init(timeIntervalSince1970:))
                )
            )
        }
        return PodcastActivityState(podcasts: podcasts)
    }

    private static func savePodcastActivityState(_ state: PodcastActivityState, database: Database) throws {
        try database.execute(sql: "DELETE FROM feedActivityObservedEpisodes")
        try database.execute(sql: "DELETE FROM feedActivityNewEpisodes")
        try database.execute(sql: "DELETE FROM feedActivityFeeds")
        for podcast in state.podcasts {
            let subscriptionID = podcast.subscriptionID.uuidString.lowercased()
            try database.execute(
                sql: "INSERT INTO feedActivityFeeds (subscriptionID, rssURL, newestPublicationDate) VALUES (?, ?, ?)",
                arguments: [subscriptionID, podcast.rssURL.absoluteString, podcast.newestPublicationDate?.timeIntervalSince1970]
            )
            var seen: Set<String> = []
            for (position, episodeID) in podcast.observedEpisodeIDs.filter({ seen.insert($0).inserted }).enumerated() {
                try database.execute(
                    sql: "INSERT INTO feedActivityObservedEpisodes (subscriptionID, episodeID, position) VALUES (?, ?, ?)",
                    arguments: [subscriptionID, episodeID, position]
                )
            }
            for episodeID in podcast.newEpisodeIDs.sorted() {
                try database.execute(
                    sql: "INSERT INTO feedActivityNewEpisodes (subscriptionID, episodeID) VALUES (?, ?)",
                    arguments: [subscriptionID, episodeID]
                )
            }
        }
    }

    private func loadRecords<Record: Decodable>(_ type: Record.Type, from table: Table) throws -> [Record] {
        let queue = try databaseQueue()
        return try queue.read { database in
            try Self.loadRecords(type, from: table, database: database)
        }
    }

    private static func loadRecords<Record: Decodable>(
        _ type: Record.Type,
        from table: Table,
        database: Database
    ) throws -> [Record] {
        let rows = try Row.fetchAll(database, sql: "SELECT recordJSON FROM \(table.rawValue) ORDER BY recordKey")
        return try rows.map { row in
            let data: Data = row["recordJSON"]
            return try makeDatabaseDecoder().decode(type, from: data)
        }
    }

    private func replaceRecords(in table: Table, with rows: [StoredRow]) throws {
        let queue = try databaseQueue()
        try queue.write { database in
            try Self.replaceRows(rows, in: table, database: database)
        }
    }

    private func mergeRows(_ rows: [StoredRow], into table: Table) throws {
        guard !rows.isEmpty else { return }
        let queue = try databaseQueue()
        try queue.write { database in
            for row in rows {
                try Self.upsert(row, into: table, database: database)
            }
        }
    }

    private static func replaceRows(_ rows: [StoredRow], in table: Table, database: Database) throws {
        try database.execute(sql: "DELETE FROM \(table.rawValue)")
        for row in rows {
            try upsert(row, into: table, database: database)
        }
    }

    private static func upsert(_ row: StoredRow, into table: Table, database: Database) throws {
        switch table {
        case .prepared:
            try database.execute(
                sql: """
                    INSERT INTO preparedEpisodes
                        (recordKey, subscriptionID, episodeID, preparedAt, recordJSON)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(recordKey) DO UPDATE SET
                        subscriptionID = excluded.subscriptionID,
                        episodeID = excluded.episodeID,
                        preparedAt = excluded.preparedAt,
                        recordJSON = excluded.recordJSON
                    """,
                arguments: [row.recordKey, row.subscriptionID, row.episodeID, row.eventDate, row.recordJSON]
            )
        case .downloaded:
            try database.execute(
                sql: """
                    INSERT INTO downloadedEpisodes
                        (recordKey, subscriptionID, episodeID, downloadedAt, recordJSON)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(recordKey) DO UPDATE SET
                        subscriptionID = excluded.subscriptionID,
                        episodeID = excluded.episodeID,
                        downloadedAt = excluded.downloadedAt,
                        recordJSON = excluded.recordJSON
                    """,
                arguments: [row.recordKey, row.subscriptionID, row.episodeID, row.eventDate, row.recordJSON]
            )
        case .removed:
            try database.execute(
                sql: """
                    INSERT INTO removedEpisodes
                        (recordKey, subscriptionID, episodeID, removedAt, recordJSON)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(recordKey) DO UPDATE SET
                        subscriptionID = excluded.subscriptionID,
                        episodeID = excluded.episodeID,
                        removedAt = excluded.removedAt,
                        recordJSON = excluded.recordJSON
                    """,
                arguments: [row.recordKey, row.subscriptionID, row.episodeID, row.eventDate, row.recordJSON]
            )
        }
    }

    private static func preparedRow(_ record: PreparedEpisode) throws -> StoredRow {
        StoredRow(
            recordKey: record.persistenceKey,
            subscriptionID: record.episode.subscriptionID?.uuidString.lowercased(),
            episodeID: record.episode.id,
            eventDate: record.preparedAt.timeIntervalSince1970,
            recordJSON: try makeDatabaseEncoder().encode(record)
        )
    }

    private static func downloadedRow(_ record: DownloadedEpisodeRecord) throws -> StoredRow {
        StoredRow(
            recordKey: record.id,
            subscriptionID: record.subscriptionID.uuidString.lowercased(),
            episodeID: record.episodeID,
            eventDate: record.downloadedAt.timeIntervalSince1970,
            recordJSON: try makeDatabaseEncoder().encode(record)
        )
    }

    private static func removedRow(_ record: RemovedEpisodeRecord) throws -> StoredRow {
        StoredRow(
            recordKey: record.id,
            subscriptionID: record.subscriptionID.uuidString.lowercased(),
            episodeID: record.episodeID,
            eventDate: record.removedAt.timeIntervalSince1970,
            recordJSON: try makeDatabaseEncoder().encode(record)
        )
    }

    private static func makeDatabaseEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDatabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let legacyImportKey = "legacyEpisodeJSONImport"
    private static let legacyAutomaticDownloadImportKey = "legacyAutomaticDownloadJSONImport"
}

struct SQLiteAppData: Equatable, Sendable {
    var preparedEpisodes: [PreparedEpisode]
    var downloadedEpisodes: [DownloadedEpisodeRecord]
    var removedEpisodes: [RemovedEpisodeRecord]
    var automaticDownloadState: AutomaticDownloadState
    var podcastActivityState: PodcastActivityState

    init(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord],
        automaticDownloadState: AutomaticDownloadState,
        podcastActivityState: PodcastActivityState
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.downloadedEpisodes = downloadedEpisodes
        self.removedEpisodes = removedEpisodes
        self.automaticDownloadState = automaticDownloadState
        self.podcastActivityState = podcastActivityState
    }
}

private enum SQLitePodcastActivityStateError: Error {
    case invalidPodcastEntry(String, String)
}

private enum SQLiteAutomaticDownloadStateError: LocalizedError {
    case invalidSubscriptionID(String)
    case invalidRSSURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidSubscriptionID(let value):
            return "Automatic download state contains an invalid subscription ID: \(value)"
        case .invalidRSSURL(let value):
            return "Automatic download state contains an invalid RSS URL: \(value)"
        }
    }
}

private extension SQLiteEpisodeStore {
    enum Table: String {
        case prepared = "preparedEpisodes"
        case downloaded = "downloadedEpisodes"
        case removed = "removedEpisodes"
    }

    struct StoredRow {
        var recordKey: String
        var subscriptionID: String?
        var episodeID: String?
        var eventDate: TimeInterval
        var recordJSON: Data
    }
}
