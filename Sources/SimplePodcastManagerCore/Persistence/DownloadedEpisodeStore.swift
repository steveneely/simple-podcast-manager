import Foundation

public protocol DownloadedEpisodeStore: Sendable {
    func loadDownloadedEpisodes() throws -> [DownloadedEpisodeRecord]
    func saveDownloadedEpisodes(_ downloadedEpisodes: [DownloadedEpisodeRecord]) throws
}
