import Foundation

public enum PodcastDiscoveryError: LocalizedError, Equatable, Sendable {
    case missingCredentials
    case invalidSearchTerm
    case invalidResponse
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Podcast discovery requires Podcast Index API credentials."
        case .invalidSearchTerm:
            return "Enter a podcast search term."
        case .invalidResponse:
            return "Podcast discovery returned an invalid response."
        case .requestFailed(let statusCode):
            return "Podcast discovery failed with HTTP \(statusCode)."
        }
    }
}
