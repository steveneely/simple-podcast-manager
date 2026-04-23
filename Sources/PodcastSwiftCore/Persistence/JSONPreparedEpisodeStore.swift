import Foundation

public struct JSONPreparedEpisodeStore: PreparedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadPreparedEpisodes() throws -> [PreparedEpisode] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode([PreparedEpisode].self, from: data)
    }

    public func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let data = try Self.makeEncoder().encode(preparedEpisodes)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return appSupportURL
            .appending(path: "PodcastSwift", directoryHint: .isDirectory)
            .appending(path: "prepared-episodes.json", directoryHint: .notDirectory)
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
