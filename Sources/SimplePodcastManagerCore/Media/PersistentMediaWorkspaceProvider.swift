import Foundation

public struct PersistentMediaWorkspaceProvider: TemporaryWorkspaceProviding {
    private let baseURL: URL

    public init(baseURL: URL = PersistentMediaWorkspaceProvider.defaultBaseURL()) {
        self.baseURL = baseURL
    }

    public func makeWorkspace() throws -> URL {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    public static func defaultBaseURL(fileManager: FileManager = .default) -> URL {
        AppIdentity.applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "PreparedMedia", directoryHint: .isDirectory)
    }
}
