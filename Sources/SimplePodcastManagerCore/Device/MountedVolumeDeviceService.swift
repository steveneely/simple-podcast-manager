import Foundation

public struct MountedVolumeDeviceService: DeviceService {
    private let mountedVolumeProvider: any MountedVolumeProviding
    private let metadataProvider: any VolumeMetadataProviding
    private let safetyValidator: SafetyValidator

    public init(
        mountedVolumeProvider: any MountedVolumeProviding = FileManagerMountedVolumeProvider(),
        metadataProvider: any VolumeMetadataProviding = FileSystemVolumeMetadataProvider(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.mountedVolumeProvider = mountedVolumeProvider
        self.metadataProvider = metadataProvider
        self.safetyValidator = safetyValidator
    }

    public func discoverDevices() throws -> [DeviceInfo] {
        let candidateDevices = mountedVolumeProvider.mountedVolumeURLs().compactMap { volumeURL in
            makeCandidateDevice(from: volumeURL)
        }

        return candidateDevices
            .filter { candidate in
                do {
                    try safetyValidator.validateDevice(candidate)
                    return true
                } catch {
                    return false
                }
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func makeCandidateDevice(from volumeURL: URL) -> DeviceInfo? {
        guard let resourceValues = try? metadataProvider.resourceValues(for: volumeURL) else {
            return nil
        }

        guard resourceValues.isDirectory else {
            return nil
        }

        guard resourceValues.isRemovable || resourceValues.isEjectable else {
            return nil
        }

        let rootURL = volumeURL.resolvingSymlinksInPath().standardizedFileURL
        let configuration = configuredDeviceConfiguration(in: rootURL)
            ?? DevicePodcastConfiguration.defaultConfiguration
        guard let podcastDirectoryURL = resolvedDirectoryURL(
            for: configuration.podcastDirectoryPath,
            in: rootURL,
            mustExist: true
        ) else {
            return nil
        }
        let playlistDirectoryURL = resolvedDirectoryURL(
            for: configuration.resolvedPlaylistDirectoryPath,
            in: rootURL,
            mustExist: false
        ) ?? podcastDirectoryURL

        return DeviceInfo(
            name: resourceValues.volumeName ?? rootURL.lastPathComponent,
            rootURL: rootURL,
            podcastDirectoryURL: podcastDirectoryURL,
            playlistDirectoryURL: playlistDirectoryURL
        )
    }

    private func resolvedDirectoryURL(
        for configuredPath: String,
        in rootURL: URL,
        mustExist: Bool
    ) -> URL? {
        let configuredURL = rootURL.appending(path: configuredPath, directoryHint: .isDirectory)
        if let existingURL = resolvedExistingDirectoryURL(for: configuredPath, in: rootURL) {
            return existingURL
        }
        if metadataProvider.directoryExists(at: configuredURL) {
            return configuredURL.standardizedFileURL
        }
        return mustExist ? nil : configuredURL.standardizedFileURL
    }

    private func resolvedExistingDirectoryURL(for relativePath: String, in rootURL: URL) -> URL? {
        var currentURL = rootURL
        for component in relativePath.split(separator: "/").map(String.init) {
            guard let childDirectories = try? metadataProvider.childDirectories(in: currentURL),
                  let matchingDirectory = childDirectories.first(where: {
                      $0.lastPathComponent.caseInsensitiveCompare(component) == .orderedSame
                  }) else {
                return nil
            }
            currentURL = matchingDirectory.standardizedFileURL
        }
        return currentURL
    }

    private func configuredDeviceConfiguration(in rootURL: URL) -> DevicePodcastConfiguration? {
        let configURL = rootURL.appending(path: DevicePodcastConfiguration.fileName, directoryHint: .notDirectory)
        guard metadataProvider.fileExists(at: configURL),
              let contents = try? metadataProvider.stringContents(of: configURL),
              let configuration = try? DevicePodcastConfiguration(contents: contents) else {
            return nil
        }

        return configuration
    }
}
