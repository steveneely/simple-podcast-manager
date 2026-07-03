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
        guard let podcastDirectoryURL = resolvedPodcastDirectoryURL(in: rootURL) else {
            return nil
        }

        return DeviceInfo(
            name: resourceValues.volumeName ?? rootURL.lastPathComponent,
            rootURL: rootURL,
            podcastDirectoryURL: podcastDirectoryURL
        )
    }

    private func resolvedPodcastDirectoryURL(in rootURL: URL) -> URL? {
        let configuredPath = configuredPodcastDirectoryPath(in: rootURL)
            ?? DevicePodcastConfiguration.defaultPodcastDirectoryPath
        let configuredURL = rootURL.appending(path: configuredPath, directoryHint: .isDirectory)
        if metadataProvider.directoryExists(at: configuredURL) {
            return configuredURL.standardizedFileURL
        }

        if configuredPath.caseInsensitiveCompare(DevicePodcastConfiguration.defaultPodcastDirectoryPath) == .orderedSame,
           let childDirectory = try? metadataProvider.childDirectories(in: rootURL).first(where: {
               $0.lastPathComponent.caseInsensitiveCompare(DevicePodcastConfiguration.defaultPodcastDirectoryPath) == .orderedSame
           }) {
            return childDirectory.standardizedFileURL
        }

        return nil
    }

    private func configuredPodcastDirectoryPath(in rootURL: URL) -> String? {
        let configURL = rootURL.appending(path: DevicePodcastConfiguration.fileName, directoryHint: .notDirectory)
        guard metadataProvider.fileExists(at: configURL),
              let contents = try? metadataProvider.stringContents(of: configURL),
              let configuration = try? DevicePodcastConfiguration(contents: contents) else {
            return nil
        }

        return configuration.podcastDirectoryPath
    }
}
