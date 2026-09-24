import Foundation

public enum DownloadServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int, detail: String? = nil)
    case missingDownloadLocation
    case insecureDownloadRequiresPermission
    case insecureDownloadFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The episode download returned an invalid response."
        case .requestFailed(let statusCode, let detail):
            let message = "The episode download failed with HTTP \(statusCode)."
            return detail.map { "\(message) \($0)" } ?? message
        case .missingDownloadLocation:
            return "The episode could not be written into the local media workspace."
        case .insecureDownloadRequiresPermission:
            return "This episode is only available over an insecure HTTP connection."
        case .insecureDownloadFailed:
            return "The insecure episode download failed."
        }
    }
}
