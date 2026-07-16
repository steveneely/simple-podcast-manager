import Foundation

public struct JSONRemovedEpisodeStore: RemovedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try AppJSONCoding.makeDecoder().decode([RemovedEpisodeRecord].self, from: data)
    }

    public func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let data = try AppJSONCoding.makeEncoder().encode(removedEpisodes)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "removed-episodes.json", directoryHint: .notDirectory)
    }
}
