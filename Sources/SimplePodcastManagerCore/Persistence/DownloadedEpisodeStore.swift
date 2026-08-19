import Foundation

public protocol DownloadedEpisodeStore: Sendable {
    func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord]
    func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws
    func mergeDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws
}

public extension DownloadedEpisodeStore {
    func mergeDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws {
        var recordsByID: [String: DownloadedEpisodeRecord] = [:]
        for downloadedEpisode in try loadDownloadedEpisodes() {
            recordsByID[downloadedEpisode.id] = downloadedEpisode
        }
        for downloadedEpisode in downloadedEpisodes {
            recordsByID[downloadedEpisode.id] = downloadedEpisode
        }
        try saveDownloadedEpisodes(Array(recordsByID.values))
    }
}
