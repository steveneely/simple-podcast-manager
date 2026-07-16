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
        return try AppJSONCoding.makeDecoder().decode([PreparedEpisode].self, from: data)
    }

    public func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let data = try AppJSONCoding.makeEncoder().encode(preparedEpisodes)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "prepared-episodes.json", directoryHint: .notDirectory)
    }
}
