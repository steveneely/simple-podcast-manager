import Foundation

public protocol VolumeMetadataProviding: Sendable {
    func resourceValues(for url: URL) throws -> MountedVolumeResourceValues
    func directoryExists(at url: URL) -> Bool
    func childDirectories(in url: URL) throws -> [URL]
    func fileExists(at url: URL) -> Bool
    func stringContents(of url: URL) throws -> String
}

public struct FileSystemVolumeMetadataProvider: VolumeMetadataProviding {
    public init() {}

    public func resourceValues(for url: URL) throws -> MountedVolumeResourceValues {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
        ])

        return MountedVolumeResourceValues(
            volumeName: values.volumeName,
            isDirectory: values.isDirectory ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false
        )
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func childDirectories(in url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.hasDirectoryPath }
    }

    public func fileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    public func stringContents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
