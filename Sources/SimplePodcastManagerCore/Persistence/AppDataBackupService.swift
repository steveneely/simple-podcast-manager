import Foundation

public struct AppDataBackupService {
    public static let backupPathExtension = "spmbackup"

    private let supportDirectoryURL: URL
    private let fileManager: FileManager
    private let episodeStore: SQLiteEpisodeStore

    public init(
        supportDirectoryURL: URL = AppIdentity.applicationSupportDirectory(),
        fileManager: FileManager = .default,
        episodeStore: SQLiteEpisodeStore? = nil
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.fileManager = fileManager
        self.episodeStore = episodeStore ?? SQLiteEpisodeStore(
            fileURL: supportDirectoryURL.appending(path: "episodes.sqlite3", directoryHint: .notDirectory),
            supportDirectoryURL: supportDirectoryURL,
            fileManager: fileManager
        )
    }

    public func exportBackup(to destinationURL: URL, exportedAt: Date = Date()) throws -> URL {
        let backupURL = normalizedBackupURL(for: destinationURL)
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        let snapshot = try currentSnapshot()
        try write(snapshot, to: backupURL, exportedAt: exportedAt)
        return backupURL
    }

    public func importBackup(from backupURL: URL, importedAt: Date = Date()) throws -> URL? {
        let manifest = try validatedManifest(at: backupURL)
        let files = Set(manifest.files)
        let unknownFiles = files.subtracting(Self.backedUpFileNames)
        guard unknownFiles.isEmpty else {
            throw AppDataBackupError.unknownFiles(Array(unknownFiles).sorted())
        }

        for fileName in files {
            try validate(fileName: fileName, at: backupURL.appending(path: fileName, directoryHint: .notDirectory))
        }

        let importedSnapshot = try snapshot(at: backupURL, includedFiles: files)
        let existingSnapshot = try currentSnapshot()
        let previousBackupURL = try backupExistingData(existingSnapshot, importedAt: importedAt)

        do {
            try apply(importedSnapshot)
        } catch {
            try? apply(existingSnapshot)
            throw error
        }

        return previousBackupURL
    }

    public static func defaultBackupFileName(date: Date = Date()) -> String {
        "SimplePodcastManager-Backup-\(backupDateFormatter.string(from: date)).\(backupPathExtension)"
    }

    private func currentSnapshot() throws -> AppDataSnapshot {
        let configurationURL = supportDirectoryURL.appending(path: "config.json", directoryHint: .notDirectory)
        let configurationData = fileManager.fileExists(atPath: configurationURL.path)
            ? try Data(contentsOf: configurationURL)
            : nil
        if configurationData != nil {
            try validate(fileName: "config.json", at: configurationURL)
        }

        let appData = try episodeStore.loadAllAppData()
        return AppDataSnapshot(
            configurationData: configurationData,
            preparedEpisodes: appData.preparedEpisodes,
            downloadedEpisodes: appData.downloadedEpisodes,
            removedEpisodes: appData.removedEpisodes,
            automaticDownloadState: appData.automaticDownloadState
        )
    }

    private func snapshot(at directoryURL: URL, includedFiles: Set<String>) throws -> AppDataSnapshot {
        func decode<Value: Decodable>(_ type: Value.Type, fileName: String, defaultValue: Value) throws -> Value {
            guard includedFiles.contains(fileName) else { return defaultValue }
            let data = try Data(contentsOf: directoryURL.appending(path: fileName, directoryHint: .notDirectory))
            return try AppJSONCoding.makeDecoder().decode(type, from: data)
        }

        let configurationData = includedFiles.contains("config.json")
            ? try Data(contentsOf: directoryURL.appending(path: "config.json", directoryHint: .notDirectory))
            : nil
        return try AppDataSnapshot(
            configurationData: configurationData,
            preparedEpisodes: decode([PreparedEpisode].self, fileName: "prepared-episodes.json", defaultValue: []),
            downloadedEpisodes: decode([DownloadedEpisodeRecord].self, fileName: "downloaded-episodes.json", defaultValue: []),
            removedEpisodes: decode([RemovedEpisodeRecord].self, fileName: "removed-episodes.json", defaultValue: []),
            automaticDownloadState: decode(
                AutomaticDownloadState.self,
                fileName: "automatic-downloads.json",
                defaultValue: AutomaticDownloadState()
            )
        )
    }

    private func apply(_ snapshot: AppDataSnapshot) throws {
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)
        try episodeStore.replaceAllAppData(
            preparedEpisodes: snapshot.preparedEpisodes,
            downloadedEpisodes: snapshot.downloadedEpisodes,
            removedEpisodes: snapshot.removedEpisodes,
            automaticDownloadState: snapshot.automaticDownloadState
        )

        let configurationURL = supportDirectoryURL.appending(path: "config.json", directoryHint: .notDirectory)
        if let configurationData = snapshot.configurationData {
            try configurationData.write(to: configurationURL, options: .atomic)
        } else if fileManager.fileExists(atPath: configurationURL.path) {
            try fileManager.removeItem(at: configurationURL)
        }
    }

    private func write(_ snapshot: AppDataSnapshot, to directoryURL: URL, exportedAt: Date) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var includedFiles = Set<String>()
        if let configurationData = snapshot.configurationData {
            try configurationData.write(
                to: directoryURL.appending(path: "config.json", directoryHint: .notDirectory),
                options: .atomic
            )
            includedFiles.insert("config.json")
        }

        try write(snapshot.preparedEpisodes, fileName: "prepared-episodes.json", to: directoryURL)
        try write(snapshot.downloadedEpisodes, fileName: "downloaded-episodes.json", to: directoryURL)
        try write(snapshot.removedEpisodes, fileName: "removed-episodes.json", to: directoryURL)
        try write(snapshot.automaticDownloadState, fileName: "automatic-downloads.json", to: directoryURL)
        includedFiles.formUnion(Self.stateFileNames)

        let manifest = AppDataBackupManifest(
            appName: AppIdentity.displayName,
            formatVersion: 1,
            exportedAt: exportedAt,
            files: includedFiles.sorted()
        )
        let manifestData = try AppJSONCoding.makeEncoder().encode(manifest)
        try manifestData.write(
            to: directoryURL.appending(path: Self.manifestFileName, directoryHint: .notDirectory),
            options: .atomic
        )
    }

    private func write<Value: Encodable>(_ value: Value, fileName: String, to directoryURL: URL) throws {
        let data = try AppJSONCoding.makeEncoder().encode(value)
        try data.write(
            to: directoryURL.appending(path: fileName, directoryHint: .notDirectory),
            options: .atomic
        )
    }

    private func backupExistingData(_ snapshot: AppDataSnapshot, importedAt: Date) throws -> URL? {
        guard snapshot.hasData else { return nil }

        let backupDirectoryURL = supportDirectoryURL.appending(path: "ImportBackups", directoryHint: .isDirectory)
        let backupURL = backupDirectoryURL.appending(
            path: "BeforeImport-\(Self.backupDateFormatter.string(from: importedAt))",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try write(snapshot, to: backupURL, exportedAt: importedAt)
        return backupURL
    }

    private func normalizedBackupURL(for destinationURL: URL) -> URL {
        guard destinationURL.pathExtension != Self.backupPathExtension else {
            return destinationURL
        }
        return destinationURL.appendingPathExtension(Self.backupPathExtension)
    }

    private func validatedManifest(at backupURL: URL) throws -> AppDataBackupManifest {
        let manifestURL = backupURL.appending(path: Self.manifestFileName, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw AppDataBackupError.missingManifest
        }

        let manifest = try AppJSONCoding.makeDecoder().decode(
            AppDataBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.appName == AppIdentity.displayName else {
            throw AppDataBackupError.invalidManifest
        }
        guard manifest.formatVersion == 1 else {
            throw AppDataBackupError.unsupportedVersion(manifest.formatVersion)
        }
        guard Set(manifest.files).count == manifest.files.count else {
            throw AppDataBackupError.invalidManifest
        }
        return manifest
    }

    private func validate(fileName: String, at fileURL: URL) throws {
        guard Self.backedUpFileNames.contains(fileName) else {
            throw AppDataBackupError.unknownFiles([fileName])
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AppDataBackupError.missingFile(fileName)
        }

        let data = try Data(contentsOf: fileURL)
        switch fileName {
        case "config.json":
            _ = try AppJSONCoding.makeDecoder().decode(AppConfiguration.self, from: data)
        case "prepared-episodes.json":
            _ = try AppJSONCoding.makeDecoder().decode([PreparedEpisode].self, from: data)
        case "downloaded-episodes.json":
            _ = try AppJSONCoding.makeDecoder().decode([DownloadedEpisodeRecord].self, from: data)
        case "removed-episodes.json":
            _ = try AppJSONCoding.makeDecoder().decode([RemovedEpisodeRecord].self, from: data)
        case "automatic-downloads.json":
            _ = try AppJSONCoding.makeDecoder().decode(AutomaticDownloadState.self, from: data)
        default:
            throw AppDataBackupError.unknownFiles([fileName])
        }
    }

    private static let manifestFileName = "manifest.json"
    private static let stateFileNames: Set<String> = [
        "prepared-episodes.json",
        "downloaded-episodes.json",
        "removed-episodes.json",
        "automatic-downloads.json",
    ]
    private static let backedUpFileNames = stateFileNames.union(["config.json"])

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct AppDataSnapshot {
    var configurationData: Data?
    var preparedEpisodes: [PreparedEpisode]
    var downloadedEpisodes: [DownloadedEpisodeRecord]
    var removedEpisodes: [RemovedEpisodeRecord]
    var automaticDownloadState: AutomaticDownloadState

    var hasData: Bool {
        configurationData != nil
            || !preparedEpisodes.isEmpty
            || !downloadedEpisodes.isEmpty
            || !removedEpisodes.isEmpty
            || !automaticDownloadState.feeds.isEmpty
    }
}

public struct AppDataBackupManifest: Codable, Equatable, Sendable {
    public var appName: String
    public var formatVersion: Int
    public var exportedAt: Date
    public var files: [String]

    public init(appName: String, formatVersion: Int, exportedAt: Date, files: [String]) {
        self.appName = appName
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.files = files
    }
}

public enum AppDataBackupError: LocalizedError, Equatable, Sendable {
    case missingManifest
    case invalidManifest
    case unsupportedVersion(Int)
    case missingFile(String)
    case unknownFiles([String])

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "That backup is missing its manifest."
        case .invalidManifest:
            return "That backup does not look like a Simple Podcast Manager backup."
        case .unsupportedVersion(let version):
            return "That backup uses unsupported format version \(version)."
        case .missingFile(let fileName):
            return "That backup is missing \(fileName)."
        case .unknownFiles(let fileNames):
            return "That backup lists unsupported files: \(fileNames.joined(separator: ", "))."
        }
    }
}
