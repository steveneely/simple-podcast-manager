import Foundation

public protocol PreparedEpisodeStore: Sendable {
    func loadPreparedEpisodes() throws -> [PreparedEpisode]
    func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws
    func mergePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws
}

public extension PreparedEpisodeStore {
    func mergePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws {
        var recordsByKey: [String: PreparedEpisode] = [:]
        for preparedEpisode in try loadPreparedEpisodes() {
            recordsByKey[preparedEpisode.persistenceKey] = preparedEpisode
        }
        for preparedEpisode in preparedEpisodes {
            recordsByKey[preparedEpisode.persistenceKey] = preparedEpisode
        }
        try savePreparedEpisodes(Array(recordsByKey.values))
    }
}
