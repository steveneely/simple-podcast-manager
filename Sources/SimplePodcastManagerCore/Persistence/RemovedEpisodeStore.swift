import Foundation

public protocol RemovedEpisodeStore: Sendable {
    func loadRemovedEpisodes() throws -> [RemovedEpisodeRecord]
    func saveRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws
    func mergeRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws
}

public extension RemovedEpisodeStore {
    func mergeRemovedEpisodes(_ removedEpisodes: [RemovedEpisodeRecord]) throws {
        var recordsByID: [String: RemovedEpisodeRecord] = [:]
        for removedEpisode in try loadRemovedEpisodes() {
            recordsByID[removedEpisode.id] = removedEpisode
        }
        for removedEpisode in removedEpisodes {
            recordsByID[removedEpisode.id] = removedEpisode
        }
        try saveRemovedEpisodes(Array(recordsByID.values))
    }
}
