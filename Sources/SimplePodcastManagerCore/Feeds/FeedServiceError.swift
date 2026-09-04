import Foundation

public enum FeedServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case invalidFeedData
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The RSS feed request returned an invalid response."
        case .invalidFeedData:
            return "The RSS feed data could not be parsed."
        case .requestFailed(let statusCode):
            return "The RSS feed request failed with HTTP \(statusCode)."
        }
    }
}
