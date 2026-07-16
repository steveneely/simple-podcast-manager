import Foundation

public struct DeviceLibrarySnapshot: Sendable {
    public let directories: [URL]
    public let files: [URL]
    private let filesByDirectory: [URL: [URL]]

    public init(
        deviceLibrary: any DeviceLibraryInspecting,
        directoryURL: URL
    ) throws {
        self.directories = try deviceLibrary.directories(in: directoryURL)
        let files = try deviceLibrary.recursiveFiles(in: directoryURL)
        self.files = files
        self.filesByDirectory = Dictionary(grouping: files) {
            $0.deletingLastPathComponent().standardizedFileURL
        }
    }

    public func directFiles(in directoryURL: URL) -> [URL] {
        filesByDirectory[directoryURL.standardizedFileURL] ?? []
    }
}
