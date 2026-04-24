import Foundation

public struct AppDataBackupService {
    public static let backupPathExtension = "spmbackup"

    private let supportDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        supportDirectoryURL: URL = AppIdentity.applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) {
        self.supportDirectoryURL = supportDirectoryURL
        self.fileManager = fileManager
    }

    public func exportBackup(to destinationURL: URL, exportedAt: Date = Date()) throws -> URL {
        let backupURL = normalizedBackupURL(for: destinationURL)
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        var includedFiles: [String] = []
        for fileName in Self.backedUpFileNames {
            let sourceURL = supportDirectoryURL.appending(path: fileName, directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            try validate(fileName: fileName, at: sourceURL)
            try fileManager.copyItem(
                at: sourceURL,
                to: backupURL.appending(path: fileName, directoryHint: .notDirectory)
            )
            includedFiles.append(fileName)
        }

        let manifest = AppDataBackupManifest(
            appName: AppIdentity.displayName,
            formatVersion: 1,
            exportedAt: exportedAt,
            files: includedFiles.sorted()
        )
        let manifestData = try Self.makeEncoder().encode(manifest)
        try manifestData.write(
            to: backupURL.appending(path: Self.manifestFileName, directoryHint: .notDirectory),
            options: .atomic
        )

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

        let previousBackupURL = try backupExistingData(importedAt: importedAt)
        try fileManager.createDirectory(at: supportDirectoryURL, withIntermediateDirectories: true)

        for fileName in Self.backedUpFileNames {
            let destinationURL = supportDirectoryURL.appending(path: fileName, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            guard files.contains(fileName) else { continue }
            try fileManager.copyItem(
                at: backupURL.appending(path: fileName, directoryHint: .notDirectory),
                to: destinationURL
            )
        }

        return previousBackupURL
    }

    public static func defaultBackupFileName(date: Date = Date()) -> String {
        "SimplePodcastManager-Backup-\(backupDateFormatter.string(from: date)).\(backupPathExtension)"
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

        let manifest = try Self.makeDecoder().decode(AppDataBackupManifest.self, from: Data(contentsOf: manifestURL))
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
            _ = try Self.makeDecoder().decode(AppConfiguration.self, from: data)
        case "prepared-episodes.json":
            _ = try Self.makeDecoder().decode([PreparedEpisode].self, from: data)
        case "downloaded-episodes.json":
            _ = try Self.makeDecoder().decode([DownloadedEpisodeRecord].self, from: data)
        case "removed-episodes.json":
            _ = try Self.makeDecoder().decode([RemovedEpisodeRecord].self, from: data)
        default:
            throw AppDataBackupError.unknownFiles([fileName])
        }
    }

    private func backupExistingData(importedAt: Date) throws -> URL? {
        let existingFileNames = Self.backedUpFileNames.filter {
            fileManager.fileExists(atPath: supportDirectoryURL.appending(path: $0, directoryHint: .notDirectory).path)
        }
        guard !existingFileNames.isEmpty else { return nil }

        let backupDirectoryURL = supportDirectoryURL.appending(path: "ImportBackups", directoryHint: .isDirectory)
        let backupURL = backupDirectoryURL.appending(
            path: "BeforeImport-\(Self.backupDateFormatter.string(from: importedAt))",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        for fileName in existingFileNames {
            try fileManager.copyItem(
                at: supportDirectoryURL.appending(path: fileName, directoryHint: .notDirectory),
                to: backupURL.appending(path: fileName, directoryHint: .notDirectory)
            )
        }
        return backupURL
    }

    private static let manifestFileName = "manifest.json"
    private static let backedUpFileNames: Set<String> = [
        "config.json",
        "prepared-episodes.json",
        "downloaded-episodes.json",
        "removed-episodes.json",
    ]

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
