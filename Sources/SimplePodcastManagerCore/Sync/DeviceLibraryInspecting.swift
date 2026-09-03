import Foundation

public protocol DeviceLibraryInspecting: Sendable {
    func files(in directoryURL: URL) throws -> [URL]
    func directories(in directoryURL: URL) throws -> [URL]
    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool
    func recursiveFiles(in directoryURL: URL) throws -> [URL]
    func recursiveFiles(
        in directoryURL: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [URL]
}

public extension DeviceLibraryInspecting {
    func directories(in directoryURL: URL) throws -> [URL] {
        []
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        try Task.checkCancellation()
        let directFiles = try files(in: directoryURL).filter { !$0.hasDirectoryPath }
        var discoveredFiles = directFiles
        for directory in try directories(in: directoryURL) {
            try Task.checkCancellation()
            discoveredFiles.append(contentsOf: try recursiveFiles(in: directory))
        }
        return discoveredFiles
    }

    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool {
        let excludedFileURLs = Set(fileURLs.map(\.standardizedFileURL))
        return try recursiveFiles(in: directoryURL).contains {
            DeviceAudioFile.isSupported($0)
                && !excludedFileURLs.contains($0.standardizedFileURL)
        }
    }

    func recursiveFiles(
        in directoryURL: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [URL] {
        let discoveredFiles = try recursiveFiles(in: directoryURL)
        progress(discoveredFiles.count)
        return discoveredFiles
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

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var directories: [URL] = []
        for case let childURL as URL in enumerator {
            try Task.checkCancellation()
            if try childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                directories.append(childURL)
            }
        }
        return directories
    }

    public func containsSupportedAudioFile(
        in directoryURL: URL,
        excluding fileURLs: Set<URL>
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return false
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let excludedFileURLs = Set(fileURLs.map(\.standardizedFileURL))
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard DeviceAudioFile.isSupported(fileURL) else { continue }
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true,
               !excludedFileURLs.contains(fileURL.standardizedFileURL) {
                return true
            }
        }
        return false
    }

    public func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        try recursiveFiles(in: directoryURL) { _ in }
    }

    public func recursiveFiles(
        in directoryURL: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [URL] {
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
            try Task.checkCancellation()
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                fileURLs.append(fileURL)
                if fileURLs.count.isMultiple(of: 100) {
                    progress(fileURLs.count)
                }
            }
        }
        progress(fileURLs.count)
        return fileURLs
    }
}
