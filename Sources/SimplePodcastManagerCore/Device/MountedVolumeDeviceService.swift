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
        guard let musicURL = resolvedMusicDirectoryURL(in: rootURL) else {
            return nil
        }

        return DeviceInfo(
            name: resourceValues.volumeName ?? rootURL.lastPathComponent,
            rootURL: rootURL,
            musicURL: musicURL
        )
    }

    private func resolvedMusicDirectoryURL(in rootURL: URL) -> URL? {
        if let childDirectory = try? metadataProvider.childDirectories(in: rootURL).first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("music") == .orderedSame
        }) {
            return childDirectory.standardizedFileURL
        }

        let fallbackURL = rootURL.appending(path: "music", directoryHint: .isDirectory)
        return metadataProvider.directoryExists(at: fallbackURL) ? fallbackURL : nil
    }
}
