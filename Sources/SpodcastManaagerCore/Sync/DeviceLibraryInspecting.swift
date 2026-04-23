import Foundation

public protocol DeviceLibraryInspecting: Sendable {
    func files(in directoryURL: URL) throws -> [URL]
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
}
