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
        let musicURL = rootURL.appending(path: "music", directoryHint: .isDirectory)
        guard metadataProvider.directoryExists(at: musicURL) else {
            return nil
        }

        return DeviceInfo(
            name: resourceValues.volumeName ?? rootURL.lastPathComponent,
            rootURL: rootURL,
            musicURL: musicURL,
            trashURL: rootURL.appending(path: ".Trashes", directoryHint: .isDirectory)
        )
    }
}
