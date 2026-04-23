import Foundation

public enum DownloadServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int)
    case missingDownloadLocation

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The episode download returned an invalid response."
        case .requestFailed(let statusCode):
            return "The episode download failed with HTTP \(statusCode)."
        case .missingDownloadLocation:
            return "The episode could not be written into the temporary workspace."
        }
    }
}
