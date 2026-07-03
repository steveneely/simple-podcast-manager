import Foundation

public protocol DeviceLibraryInspecting: Sendable {
    func files(in directoryURL: URL) throws -> [URL]
    func directories(in directoryURL: URL) throws -> [URL]
    func recursiveFiles(in directoryURL: URL) throws -> [URL]
}

public extension DeviceLibraryInspecting {
    func directories(in directoryURL: URL) throws -> [URL] {
        []
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        let directFiles = try files(in: directoryURL).filter { !$0.hasDirectoryPath }
        let nestedFiles = try directories(in: directoryURL).flatMap { try recursiveFiles(in: $0) }
        return directFiles + nestedFiles
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

        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try children.filter {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
    }

    public func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                fileURLs.append(fileURL)
            }
        }
        return fileURLs
    }
}
