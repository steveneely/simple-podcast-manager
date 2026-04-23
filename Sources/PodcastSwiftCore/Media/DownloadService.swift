import Foundation

public protocol DownloadService: Sendable {
    func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL
}
