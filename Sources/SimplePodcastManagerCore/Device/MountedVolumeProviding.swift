import Foundation

public protocol MountedVolumeProviding: Sendable {
    func mountedVolumeURLs() -> [URL]
}

public struct FileManagerMountedVolumeProvider: MountedVolumeProviding {
    public init() {}

    public func mountedVolumeURLs() -> [URL] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .isDirectoryKey,
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
            ],
            options: [.skipHiddenVolumes]
        ) ?? []
    }
}
