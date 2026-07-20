import Foundation

public enum SyncExecutionError: LocalizedError, Equatable, Sendable {
    case destinationAlreadyExists(URL)
    case copyFailed(fileName: String, partialFileMayRemain: Bool, detail: String)
    case ejectFailed(String, String? = nil)

    public var errorDescription: String? {
        switch self {
        case .destinationAlreadyExists(let url):
            return "\(url.lastPathComponent) appeared on the device after the sync was planned. Rebuild the plan and try again."
        case .copyFailed(let fileName, let partialFileMayRemain, let detail):
            let partialCopyMessage = partialFileMayRemain
                ? " A partial file may remain on the device; select it for deletion before trying again."
                : ""
            return "Could not copy \(fileName): \(detail).\(partialCopyMessage)"
        case .ejectFailed(let path, let detail):
            let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedDetail, !trimmedDetail.isEmpty {
                return "Could not eject the device at \(path): \(trimmedDetail)"
            }
            return "Could not eject the device at \(path)."
        }
    }
}
