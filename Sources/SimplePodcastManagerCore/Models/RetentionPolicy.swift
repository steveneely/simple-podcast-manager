import Foundation

public enum RetentionPolicy: Codable, Equatable, Sendable {
    case keepLatestEpisodes(Int)

    public var episodeLimit: Int {
        switch self {
        case .keepLatestEpisodes(let count):
            return count
        }
    }
}
