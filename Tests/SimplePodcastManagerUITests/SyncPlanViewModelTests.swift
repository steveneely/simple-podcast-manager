import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncPlanViewModelTests {
    @Test
    func buildPlanProducesActionDescriptions() async {
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
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
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let planner = SyncPlanner(deviceLibrary: StubPlanDeviceLibrary(filesByDirectory: [:]))
        let viewModel = SyncPlanViewModel(planner: planner)

        await viewModel.buildPlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            manualDeleteTargets: [],
            ejectAfterSync: true
        )

        #expect(viewModel.plan != nil)
        #expect(viewModel.actionDescriptions.contains(where: { $0.contains("Copy to device") }))
        #expect(viewModel.actionDescriptions.contains("Eject device when finished"))
    }

    @Test
    func buildPlanWithoutDeviceSurfacesError() async {
        let viewModel = SyncPlanViewModel()

        await viewModel.buildPlan(
            device: nil,
            preparedEpisodes: [],
            subscriptions: [],
            manualDeleteTargets: [],
            ejectAfterSync: false
        )

        #expect(viewModel.plan == nil)
        #expect(!viewModel.isPlanning)
        #expect(viewModel.lastErrorMessage == "Select a compatible device before building a sync plan.")
    }

    @Test
    func buildPlanInspectsDeviceOutsideMainThread() async {
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
        )
        let deviceLibrary = ThreadCapturingPlanDeviceLibrary()
        let viewModel = SyncPlanViewModel(planner: SyncPlanner(deviceLibrary: deviceLibrary))

        await viewModel.buildPlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [],
            ejectAfterSync: false
        )

        #expect(deviceLibrary.allRequestsWereOffMainThread)
    }
}

private struct StubPlanDeviceLibrary: DeviceLibraryInspecting {
    let filesByDirectory: [String: [URL]]

    func files(in directoryURL: URL) throws -> [URL] {
        filesByDirectory[directoryURL.standardizedFileURL.path] ?? []
    }
}

private final class ThreadCapturingPlanDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var requestMainThreadValues: [Bool] = []

    var allRequestsWereOffMainThread: Bool {
        lock.withLock {
            !requestMainThreadValues.isEmpty && requestMainThreadValues.allSatisfy { !$0 }
        }
    }

    func files(in directoryURL: URL) throws -> [URL] {
        recordRequest()
        return []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        recordRequest()
        return []
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        recordRequest()
        return []
    }

    private func recordRequest() {
        lock.withLock {
            requestMainThreadValues.append(Thread.isMainThread)
        }
    }
}
