import Foundation

public enum SafetyValidationError: LocalizedError, Equatable, Sendable {
    case invalidDeviceRoot(URL)
    case invalidPodcastDirectory(URL)
    case pathOutsideDevicePodcastDirectory(URL)
    case pathOutsideDeviceRoot(URL)
    case macTrashPathNotAllowed(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidDeviceRoot(let url):
            return "The selected device is not available at a safe mounted-volume path: \(url.path)."
        case .invalidPodcastDirectory(let url):
            return "The configured podcast folder is not safely contained inside the selected device: \(url.path)."
        case .pathOutsideDevicePodcastDirectory(let url):
            return "The proposed file is outside the configured podcast folder, so SPM will not change it: \(url.path)."
        case .pathOutsideDeviceRoot(let url):
            return "The proposed action is outside the selected device, so SPM will not perform it: \(url.path)."
        case .macTrashPathNotAllowed(let url):
            return "SPM will not change files in the Mac Trash: \(url.path)."
        }
    }
}
