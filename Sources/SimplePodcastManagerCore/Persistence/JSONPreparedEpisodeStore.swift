import Foundation

public struct JSONPreparedEpisodeStore: PreparedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadPreparedEpisodes() throws -> [PreparedEpisode] {
        try AppJSONFile.load([PreparedEpisode].self, from: fileURL, defaultValue: [])
    }

    public func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        try AppJSONFile.save(preparedEpisodes, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "prepared-episodes.json", directoryHint: .notDirectory)
    }
}
