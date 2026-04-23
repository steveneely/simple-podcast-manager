import Foundation
import Observation
import PodcastSwiftCore

@MainActor
@Observable
public final class DiscoveryViewModel {
    public var searchText: String
    public private(set) var results: [DiscoveryResult]
    public private(set) var isSearching: Bool
    public private(set) var errorMessage: String?

    private let serviceFactory: @Sendable (AppSettings) -> (any PodcastDiscoveryService)?

    public init(
        searchText: String = "",
        serviceFactory: @escaping @Sendable (AppSettings) -> (any PodcastDiscoveryService)? = DiscoveryViewModel.defaultServiceFactory
    ) {
        self.searchText = searchText
        self.results = []
        self.isSearching = false
        self.errorMessage = nil
        self.serviceFactory = serviceFactory
    }

    public var hasResults: Bool {
        !results.isEmpty
    }

    public func search(using settings: AppSettings) async {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            results = []
            errorMessage = PodcastDiscoveryError.invalidSearchTerm.localizedDescription
            return
        }

        guard let service = serviceFactory(settings) else {
            results = []
            errorMessage = PodcastDiscoveryError.missingCredentials.localizedDescription
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await service.searchPodcasts(matching: normalizedQuery)
            errorMessage = nil
        } catch {
            results = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    public nonisolated static func defaultServiceFactory(settings: AppSettings) -> (any PodcastDiscoveryService)? {
        guard
            let apiKey = settings.podcastIndexAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            let apiSecret = settings.podcastIndexAPISecret?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty,
            !apiSecret.isEmpty
        else {
            return nil
        }

        return PodcastIndexDiscoveryService(
            credentials: PodcastDirectoryCredentials(apiKey: apiKey, apiSecret: apiSecret)
        )
    }
}
