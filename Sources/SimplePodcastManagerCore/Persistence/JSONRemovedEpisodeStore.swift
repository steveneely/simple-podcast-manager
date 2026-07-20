import Foundation

public struct JSONRemovedEpisodeStore: RemovedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord] {
        try AppJSONFile.load([RemovedEpisodeRecord].self, from: fileURL, defaultValue: [])
    }

    public func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        try AppJSONFile.save(removedEpisodes, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "removed-episodes.json", directoryHint: .notDirectory)
    }
}
