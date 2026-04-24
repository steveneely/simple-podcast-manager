import Foundation

public enum SyncExecutionError: LocalizedError, Equatable, Sendable {
    case missingParentDirectory(URL)
    case ejectFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingParentDirectory(let url):
            return "Could not resolve a safe parent directory for \(url.path)."
        case .ejectFailed(let path):
            return "Could not eject the device at \(path)."
        }
    }
}
