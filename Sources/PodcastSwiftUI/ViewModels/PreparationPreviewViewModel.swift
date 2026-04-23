import Foundation
import Observation
import PodcastSwiftCore

@MainActor
@Observable
public final class PreparationPreviewViewModel {
    public private(set) var preparedEpisodes: [PreparedEpisode]
    public private(set) var failures: [PreparationFailure]
    public private(set) var workspaceURL: URL?
    public private(set) var isPreparing: Bool
    public private(set) var lastErrorMessage: String?

    private let service: MediaPreparationService

    public init(service: MediaPreparationService = MediaPreparationService()) {
        self.service = service
        self.preparedEpisodes = []
        self.failures = []
        self.workspaceURL = nil
        self.isPreparing = false
        self.lastErrorMessage = nil
    }

    public var hasResults: Bool {
        !preparedEpisodes.isEmpty || !failures.isEmpty
    }

    public func prepare(_ episodes: [Episode], settings: AppSettings) async {
        isPreparing = true
        defer { isPreparing = false }

        do {
            let result = try await service.prepareEpisodes(episodes, settings: settings)
            preparedEpisodes = result.preparedEpisodes
            failures = result.failures
            workspaceURL = result.workspaceURL
            lastErrorMessage = nil
        } catch {
            preparedEpisodes = []
            failures = []
            workspaceURL = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
