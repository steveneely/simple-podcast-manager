import Foundation

public protocol DownloadService: Sendable {
    func download(
        _ episode: Episode,
        into workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> URL
}
