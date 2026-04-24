import Foundation

public protocol AudioConversionService: Sendable {
    func prepareAudio(for episode: Episode, sourceFileURL: URL, in workspaceURL: URL, settings: AppSettings) async throws -> PreparedEpisode
}
