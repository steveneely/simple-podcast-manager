import Foundation
import Testing
@testable import SpodcastManaagerCore
@testable import SpodcastManaagerUI

@MainActor
struct SyncPlanViewModelTests {
    @Test
    func buildPlanProducesActionDescriptions() {
        let device = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/WALKMAN/.Trashes", isDirectory: true)
        )
        let preparedEpisode = PreparedEpisode(
            episode: Episode(
                id: "ep-1",
                subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                podcastTitle: "Example Podcast",
                title: "Episode 1",
                enclosureURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            ),
            sourceFileURL: URL(fileURLWithPath: "/tmp/Episode_1.mp3"),
            preparedFileURL: URL(fileURLWithPath: "/tmp/Episode_1.mp3"),
            preparationAction: .passthroughMP3
        )
        let subscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!,
            retentionPolicy: .keepLatestEpisodes(3)
        )
        let planner = SyncPlanner(deviceLibrary: StubPlanDeviceLibrary(filesByDirectory: [:]))
        let viewModel = SyncPlanViewModel(planner: planner)

        viewModel.buildPlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            manualDeleteTargets: [],
            ejectAfterSync: true,
            isDryRun: true
        )

        #expect(viewModel.plan != nil)
        #expect(viewModel.actionDescriptions.contains(where: { $0.contains("Copy to device") }))
        #expect(viewModel.actionDescriptions.contains("Clear device trash"))
        #expect(viewModel.actionDescriptions.contains("Eject device after sync"))
    }

    @Test
    func buildPlanWithoutDeviceSurfacesError() {
        let viewModel = SyncPlanViewModel()

        viewModel.buildPlan(
            device: nil,
            preparedEpisodes: [],
            subscriptions: [],
            manualDeleteTargets: [],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(viewModel.plan == nil)
        #expect(viewModel.lastErrorMessage == "Select a compatible device before building a sync plan.")
    }
}

private struct StubPlanDeviceLibrary: DeviceLibraryInspecting {
    let filesByDirectory: [String: [URL]]

    func files(in directoryURL: URL) throws -> [URL] {
        filesByDirectory[directoryURL.standardizedFileURL.path] ?? []
    }
}
