import Foundation
import GRDB

public final class SQLiteEpisodeStore: PreparedEpisodeStore, DownloadedEpisodeStore, RemovedEpisodeStore, @unchecked Sendable {
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

    func loadAllEpisodeData() throws -> SQLiteEpisodeData {
        let queue = try databaseQueue()
        return try queue.read { database in
            try SQLiteEpisodeData(
                preparedEpisodes: Self.loadRecords(PreparedEpisode.self, from: .prepared, database: database),
                downloadedEpisodes: Self.loadRecords(DownloadedEpisodeRecord.self, from: .downloaded, database: database),
                removedEpisodes: Self.loadRecords(RemovedEpisodeRecord.self, from: .removed, database: database)
            )
        }
    }

    public func replaceAllEpisodeData(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord]
    ) throws {
        let queue = try databaseQueue()
        try queue.write { database in
            try Self.replaceRows(try preparedEpisodes.map(Self.preparedRow), in: .prepared, database: database)
            try Self.replaceRows(try downloadedEpisodes.map(Self.downloadedRow), in: .downloaded, database: database)
            try Self.replaceRows(try removedEpisodes.map(Self.removedRow), in: .removed, database: database)
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
        try migrator.migrate(queue)
        try importLegacyJSONIfNeeded(into: queue)
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
}

struct SQLiteEpisodeData: Equatable, Sendable {
    var preparedEpisodes: [PreparedEpisode]
    var downloadedEpisodes: [DownloadedEpisodeRecord]
    var removedEpisodes: [RemovedEpisodeRecord]

    init(
        preparedEpisodes: [PreparedEpisode],
        downloadedEpisodes: [DownloadedEpisodeRecord],
        removedEpisodes: [RemovedEpisodeRecord]
    ) {
        self.preparedEpisodes = preparedEpisodes
        self.downloadedEpisodes = downloadedEpisodes
        self.removedEpisodes = removedEpisodes
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
