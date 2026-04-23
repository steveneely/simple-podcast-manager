import Foundation

public protocol PreparedEpisodeStore: Sendable {
    func loadPreparedEpisodes() throws -> [PreparedEpisode]
    func savePreparedEpisodes(_ preparedEpisodes: [PreparedEpisode]) throws
}
