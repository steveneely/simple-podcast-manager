import Foundation

public struct JSONDownloadedEpisodeStore: DownloadedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode([DownloadedEpisodeRecord].self, from: data)
    }

    public func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let data = try Self.makeEncoder().encode(downloadedEpisodes)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "downloaded-episodes.json", directoryHint: .notDirectory)
    }

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
