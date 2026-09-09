import Foundation

public enum MediaPreparationResult: Equatable, Sendable {
    case prepared(PreparedEpisode)
    case failed(PreparationFailure)
    case cancelled
}
