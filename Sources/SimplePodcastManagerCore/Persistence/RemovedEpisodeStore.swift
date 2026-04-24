import Foundation

public protocol RemovedEpisodeStore: Sendable {
    func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord]
    func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws
}
