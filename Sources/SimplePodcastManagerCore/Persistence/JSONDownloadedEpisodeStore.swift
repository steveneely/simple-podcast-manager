import Foundation

public struct JSONDownloadedEpisodeStore: DownloadedEpisodeStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord] {
        try AppJSONFile.load([DownloadedEpisodeRecord].self, from: fileURL, defaultValue: [])
    }

    public func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        try AppJSONFile.save(downloadedEpisodes, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "downloaded-episodes.json", directoryHint: .notDirectory)
    }
}
