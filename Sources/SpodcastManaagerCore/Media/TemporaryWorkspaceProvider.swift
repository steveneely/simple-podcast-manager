import Foundation

public protocol TemporaryWorkspaceProviding: Sendable {
    func makeWorkspace() throws -> URL
}

public struct TemporaryWorkspaceProvider: TemporaryWorkspaceProviding {
    public init() {}

    public func makeWorkspace() throws -> URL {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpodcastManaager", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }
}
