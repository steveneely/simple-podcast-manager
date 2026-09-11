import Foundation

public struct SafetyValidator: Sendable {
    private let homeDirectoryURL: URL

    public init(homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.homeDirectoryURL = homeDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public func validateDevice(_ device: DeviceInfo) throws {
        let rootURL = canonicalDirectoryURL(device.rootURL)
        let podcastDirectoryURL = canonicalDirectoryURL(device.podcastDirectoryURL)

        guard rootURL.path.hasPrefix("/Volumes/") else {
            throw SafetyValidationError.invalidDeviceRoot(device.rootURL)
        }

        guard isContained(podcastDirectoryURL, within: rootURL),
              podcastDirectoryURL != rootURL else {
            throw SafetyValidationError.invalidPodcastDirectory(podcastDirectoryURL)
        }
    }

    public func validateWriteTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validateDevice(device)

        let canonicalTargetURL = canonicalFileURL(targetURL)
        let canonicalPodcastDirectoryURL = canonicalDirectoryURL(device.podcastDirectoryURL)

        try validateNotMacTrash(canonicalTargetURL)

        guard isContained(canonicalTargetURL, within: canonicalPodcastDirectoryURL) else {
            throw SafetyValidationError.pathOutsideDevicePodcastDirectory(canonicalTargetURL)
        }
    }

    public func validateDeleteTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validateWriteTarget(targetURL, on: device)
    }

    public func validatePodcastPlaylistTarget(_ targetURL: URL, on device: DeviceInfo) throws {
        try validatePodcastPlaylistTarget(
            targetURL,
            in: device.playlistDirectoryURL,
            on: device
        )
    }

    public func validatePodcastPlaylistTarget(
        _ targetURL: URL,
        in playlistDirectoryURL: URL,
        on device: DeviceInfo
    ) throws {
        try validateDevice(device)
        let canonicalTargetURL = canonicalFileURL(targetURL)
        let canonicalPlaylistDirectoryURL = canonicalDirectoryURL(playlistDirectoryURL)
        let canonicalRootURL = canonicalDirectoryURL(device.rootURL)
        guard isContained(canonicalPlaylistDirectoryURL, within: canonicalRootURL),
              canonicalPlaylistDirectoryURL != canonicalRootURL else {
            throw SafetyValidationError.invalidPlaylistDirectory(canonicalPlaylistDirectoryURL)
        }
        try validateNotMacTrash(canonicalTargetURL)
        guard canonicalTargetURL.deletingLastPathComponent() == canonicalPlaylistDirectoryURL.standardizedFileURL,
              canonicalTargetURL.pathExtension.lowercased() == "m3u",
              !canonicalTargetURL.lastPathComponent.hasPrefix("._") else {
            throw SafetyValidationError.invalidPodcastPlaylistTarget(canonicalTargetURL)
        }
    }

    public func validatePodcastPlaylistSidecarTarget(
        _ sidecarURL: URL,
        for playlistURL: URL,
        in playlistDirectoryURL: URL? = nil,
        on device: DeviceInfo
    ) throws {
        try validatePodcastPlaylistTarget(
            playlistURL,
            in: playlistDirectoryURL ?? device.playlistDirectoryURL,
            on: device
        )
        let canonicalSidecarURL = canonicalFileURL(sidecarURL)
        let expectedSidecarURL = canonicalFileURL(
            playlistURL.deletingLastPathComponent()
                .appendingPathComponent("._" + playlistURL.lastPathComponent)
        )
        try validateNotMacTrash(canonicalSidecarURL)
        guard canonicalSidecarURL == expectedSidecarURL else {
            throw SafetyValidationError.invalidPodcastPlaylistTarget(canonicalSidecarURL)
        }
    }

    public func validate(_ action: SyncAction, on device: DeviceInfo) throws {
        switch action {
        case .copyToDevice(_, let destinationURL, _):
            try validateWriteTarget(destinationURL, on: device)
        case .deleteFromDevice(let targetURL, _):
            try validateDeleteTarget(targetURL, on: device)
        case .writePodcastPlaylist(let destinationURL, _, _):
            try validatePodcastPlaylistTarget(destinationURL, on: device)
        case .deletePodcastPlaylist(let targetURL), .deleteEmptyPodcastPlaylist(let targetURL):
            try validatePodcastPlaylistTarget(targetURL, on: device)
        case .deleteRelocatedPodcastPlaylist(let targetURL, let playlistDirectoryURL):
            try validatePodcastPlaylistTarget(targetURL, in: playlistDirectoryURL, on: device)
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
