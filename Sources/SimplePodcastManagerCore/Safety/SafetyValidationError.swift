import Foundation

public enum SafetyValidationError: Error, Equatable, Sendable {
    case invalidDeviceRoot(URL)
    case invalidPodcastDirectory(URL)
    case pathOutsideDevicePodcastDirectory(URL)
    case pathOutsideDeviceRoot(URL)
    case macTrashPathNotAllowed(URL)
}
