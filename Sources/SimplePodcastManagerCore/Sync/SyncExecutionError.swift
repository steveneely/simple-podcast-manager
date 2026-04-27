import Foundation

public enum SyncExecutionError: LocalizedError, Equatable, Sendable {
    case missingParentDirectory(URL)
    case ejectFailed(String, String? = nil)

    public var errorDescription: String? {
        switch self {
        case .missingParentDirectory(let url):
            return "Could not resolve a safe parent directory for \(url.path)."
        case .ejectFailed(let path, let detail):
            let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedDetail, !trimmedDetail.isEmpty {
                return "Could not eject the device at \(path): \(trimmedDetail)"
            }
            return "Could not eject the device at \(path)."
        }
    }
}
