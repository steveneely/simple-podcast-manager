import Foundation

public struct SafetyValidator: Sendable {
    private let homeDirectoryURL: URL

    public init(homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.homeDirectoryURL = homeDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public func validateDevice(_ device: DeviceInfo) throws {
        let rootURL = canonicalDirectoryURL(device.rootURL)
        let expectedMusicURL = rootURL.appending(path: "music", directoryHint: .isDirectory)
        let expectedTrashURL = rootURL.appending(path: ".Trashes", directoryHint: .isDirectory)
        let actualMusicURL = canonicalDirectoryURL(device.musicURL)
        let actualTrashURL = canonicalDirectoryURL(device.trashURL)

        guard rootURL.path.hasPrefix("/Volumes/") else {
            throw SafetyValidationError.invalidDeviceRoot(device.rootURL)
        }

        guard actualMusicURL == expectedMusicURL else {
            throw SafetyValidationError.invalidMusicDirectory(expected: expectedMusicURL, actual: actualMusicURL)
        }

        guard actualTrashURL == expectedTrashURL else {
            throw SafetyValidationError.invalidTrashDirectory(expected: expectedTrashURL, actual: actualTrashURL)
        }
    }

    public func validateWriteTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validateDevice(device)

        let canonicalTargetURL = canonicalFileURL(targetURL)
        let canonicalMusicURL = canonicalDirectoryURL(device.musicURL)

        try validateNotMacTrash(canonicalTargetURL)

        guard isContained(canonicalTargetURL, within: canonicalMusicURL) else {
            throw SafetyValidationError.pathOutsideDeviceMusic(canonicalTargetURL)
        }
    }

    public func validateDeleteTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validateWriteTarget(targetURL, on: device)
    }

    public func validateClearTrashTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validateDevice(device)

        let canonicalTargetURL = canonicalDirectoryURL(targetURL)
        let canonicalTrashURL = canonicalDirectoryURL(device.trashURL)

        try validateNotMacTrash(canonicalTargetURL)

        guard canonicalTargetURL == canonicalTrashURL else {
            throw SafetyValidationError.clearTrashRequiresExactDeviceTrash(canonicalTargetURL)
        }
    }

    public func validate(_ action: SyncAction, on device: DeviceInfo) throws {
        switch action {
        case .copyToDevice(_, let destinationURL):
            try validateWriteTarget(destinationURL, on: device)
        case .deleteFromDevice(let targetURL):
            try validateDeleteTarget(targetURL, on: device)
        case .clearDeviceTrash(let trashURL):
            try validateClearTrashTarget(trashURL, on: device)
        case .ejectDevice(let deviceRootURL):
            let canonicalDeviceRootURL = canonicalDirectoryURL(device.rootURL)
            let canonicalActionRootURL = canonicalDirectoryURL(deviceRootURL)
            guard canonicalDeviceRootURL == canonicalActionRootURL else {
                throw SafetyValidationError.pathOutsideDeviceRoot(canonicalActionRootURL)
            }
        case .skip:
            break
        }
    }

    private func validateNotMacTrash(_ targetURL: URL) throws {
        let macTrashURL = canonicalDirectoryURL(homeDirectoryURL.appending(path: ".Trash", directoryHint: .isDirectory))
        if targetURL == macTrashURL || isContained(targetURL, within: macTrashURL) {
            throw SafetyValidationError.macTrashPathNotAllowed(targetURL)
        }
    }

    private func canonicalDirectoryURL(_ url: URL) -> URL {
        canonicalFileURL(url).appendingPathComponent("", isDirectory: true)
    }

    private func canonicalFileURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func isContained(_ candidate: URL, within directory: URL) -> Bool {
        let directoryPath = canonicalDirectoryURL(directory).path
        let candidatePath = canonicalFileURL(candidate).path
        return candidatePath.hasPrefix(directoryPath)
    }
}
