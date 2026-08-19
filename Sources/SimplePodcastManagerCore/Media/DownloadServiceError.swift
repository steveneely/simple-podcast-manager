import Foundation

public enum DownloadServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int)
    case missingDownloadLocation
    case insecureDownloadRequiresPermission
    case insecureDownloadFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The episode download returned an invalid response."
        case .requestFailed(let statusCode):
            return "The episode download failed with HTTP \(statusCode)."
        case .missingDownloadLocation:
            return "The episode could not be written into the local media workspace."
        case .insecureDownloadRequiresPermission:
            return "This episode is only available over an insecure HTTP connection."
        case .insecureDownloadFailed:
            return "The insecure episode download failed."
        }
    }
}
