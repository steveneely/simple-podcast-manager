import Foundation

public enum SafetyValidationError: Error, Equatable, Sendable {
    case invalidDeviceRoot(URL)
    case invalidMusicDirectory(expected: URL, actual: URL)
    case invalidTrashDirectory(expected: URL, actual: URL)
    case pathOutsideDeviceMusic(URL)
    case pathOutsideDeviceRoot(URL)
    case macTrashPathNotAllowed(URL)
    case clearTrashRequiresExactDeviceTrash(URL)
}
