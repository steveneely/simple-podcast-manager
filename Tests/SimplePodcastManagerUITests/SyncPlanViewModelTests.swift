import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncPlanViewModelTests {
    @Test
    func buildPlanProducesTypedActions() async {
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
        let planner = makeTestPlanner(deviceLibrary: StubPlanDeviceLibrary(filesByDirectory: [:]))
        let viewModel = SyncPlanViewModel(planner: planner)

        await viewModel.buildPlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            manualDeleteTargets: [],
            ejectAfterSync: true
        )

        #expect(viewModel.plan != nil)
        #expect(viewModel.plan?.actions.contains(where: { if case .copyToDevice = $0 { true } else { false } }) == true)
        #expect(viewModel.plan?.actions.contains(where: { if case .ejectDevice = $0 { true } else { false } }) == true)

        viewModel.prepareForPlanRebuild()

        #expect(viewModel.plan == nil)
        #expect(viewModel.isPlanning)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test
    func insufficientSpaceClearsPlanAndSurfacesCapacityError() async {
        let subscriptionID = UUID()
        let device = DeviceInfo(
            name: "Small Test Disk",
            rootURL: URL(fileURLWithPath: "/Volumes/SMALL-TEST-DISK", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SMALL-TEST-DISK/music", isDirectory: true)
        )
        let preparedEpisode = PreparedEpisode(
            episode: Episode(
                id: "large-episode",
                subscriptionID: subscriptionID,
                podcastTitle: "Example Podcast",
                title: "Large Episode",
                enclosureURL: URL(string: "https://cdn.example.com/large.mp3")!,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            ),
            sourceFileURL: URL(fileURLWithPath: "/tmp/large.mp3"),
            preparedFileURL: URL(fileURLWithPath: "/tmp/large.mp3"),
            preparationAction: .passthroughMP3
        )
        let planner = makeTestPlanner(
            deviceLibrary: StubPlanDeviceLibrary(filesByDirectory: [:]),
            storageInspector: TestUISyncStorageInspector(availableBytes: 10, fileSizeBytes: 100)
        )
        let viewModel = SyncPlanViewModel(planner: planner)

        await viewModel.buildPlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [
                FeedSubscription(
                    id: subscriptionID,
                    title: "Example Podcast",
                    rssURL: URL(string: "https://example.com/feed.xml")!
                )
            ],
            ejectAfterSync: false
        )

        #expect(viewModel.plan == nil)
        #expect(!viewModel.isPlanning)
        #expect(viewModel.lastErrorMessage?.contains("free space") == true)
        #expect(viewModel.lastErrorMessage?.contains("selected deletions") == false)
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
    func buildPlanKeepsExcludedCleanupCandidateVisibleWithoutDeletingIt() async throws {
        let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
        )
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let oldEpisodeURL = managedDirectory.appendingPathComponent("2026.01.01-Old Episode-(Example Podcast).mp3")
        let newerEpisodeURLs = (2...4).map { day in
            managedDirectory.appendingPathComponent("2026.01.0\(day)-Episode \(day)-(Example Podcast).mp3")
        }
        let planner = makeTestPlanner(
            deviceLibrary: StubPlanDeviceLibrary(
                filesByDirectory: [device.podcastDirectoryURL.path: [oldEpisodeURL] + newerEpisodeURLs]
            )
        )
        let viewModel = SyncPlanViewModel(planner: planner)

        await viewModel.buildPlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [
                FeedSubscription(
                    id: subscriptionID,
                    title: "Example Podcast",
                    rssURL: URL(string: "https://example.com/feed.xml")!
                )
            ],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            excludedCleanupTargets: [oldEpisodeURL],
            ejectAfterSync: false
        )

        #expect(viewModel.plan?.cleanupCandidates.map(\.targetURL) == [oldEpisodeURL])
        #expect(viewModel.plan?.actions.isEmpty == true)
    }

    @Test
    func buildPlanInspectsDeviceOutsideMainThread() async {
        let device = DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
        )
        let deviceLibrary = ThreadCapturingPlanDeviceLibrary()
        let viewModel = SyncPlanViewModel(planner: makeTestPlanner(deviceLibrary: deviceLibrary))

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
