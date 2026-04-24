import Foundation

public protocol DeviceLibraryInspecting: Sendable {
    func files(in directoryURL: URL) throws -> [URL]
    func directories(in directoryURL: URL) throws -> [URL]
}

public extension DeviceLibraryInspecting {
    func directories(in directoryURL: URL) throws -> [URL] {
        []
    }
}

public struct FileSystemDeviceLibrary: DeviceLibraryInspecting {
    public init() {}

    public func files(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    public func directories(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.hasDirectoryPath }
    }
}
