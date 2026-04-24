import Foundation
import Testing
@testable import SPodcastManagerCore

struct SyncPlannerTests {
    @Test
    func plansCopyForPreparedEpisodeMissingFromDevice() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let planner = SyncPlanner(deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]))

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(
            plan.actions.contains(.copyToDevice(
                sourceURL: preparedEpisode.preparedFileURL,
                destinationURL: device.musicURL
                    .appendingPathComponent("Example Podcast", isDirectory: true)
                    .appendingPathComponent("Episode_1.mp3", isDirectory: false)
            ))
        )
    }

    @Test
    func skipsCopyWhenDestinationAlreadyExists() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let destinationURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("Example Podcast", isDirectory: true).standardizedFileURL.path: [destinationURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(plan.actions.contains(.skip(reason: "Already on device: Episode 1")))
        #expect(!plan.actions.contains(where: {
            if case .copyToDevice = $0 { return true }
            return false
        }))
    }

    @Test
    func appleDoubleSidecarDoesNotCountAsExistingEpisodeOnDevice() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "2026.04.21-Episode 1-(Example Podcast).mp3"
        )
        let sidecarURL = device.musicURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("._2026.04.21-Episode 1-(Example Podcast).mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("Example Podcast", isDirectory: true).standardizedFileURL.path: [sidecarURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(plan.actions.contains(where: {
            guard case .copyToDevice(_, let destinationURL) = $0 else { return false }
            return destinationURL.lastPathComponent == preparedEpisode.preparedFileURL.lastPathComponent
        }))
    }

    @Test
    func doesNotAutoDeleteManagedEpisodesWithoutManualSelection() throws {
        let device = makeDevice()
        let subscription = makeSubscription(retentionLimit: 2)
        let preparedEpisodes = [
            makePreparedEpisode(id: "ep-3", title: "Episode 3", preparedFileName: "Episode_3.mp3"),
            makePreparedEpisode(id: "ep-2", title: "Episode 2", preparedFileName: "Episode_2.mp3"),
        ]
        let managedDirectory = device.musicURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let olderEpisodeURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let currentEpisodeURL = managedDirectory.appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    managedDirectory.standardizedFileURL.path: [
                        olderEpisodeURL,
                        currentEpisodeURL,
                    ]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: preparedEpisodes,
            subscriptions: [subscription],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: olderEpisodeURL)))
        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: currentEpisodeURL)))
    }

    @Test
    func doesNotDeleteFilesOutsideManagedPodcastFolders() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let unmanagedFileURL = device.musicURL.appendingPathComponent("random_track.mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.standardizedFileURL.path: [unmanagedFileURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: unmanagedFileURL)))
    }

    @Test
    func plansTrashCleanupWhenDeletingAndOptionalEject() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.musicURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let existingFileURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    managedDirectory.standardizedFileURL.path: [existingFileURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [subscription],
            manualDeleteTargets: [existingFileURL],
            ejectAfterSync: true,
            isDryRun: true
        )

        #expect(plan.actions.contains(.clearDeviceTrash(trashURL: device.trashURL)))
        #expect(plan.actions.contains(.ejectDevice(deviceRootURL: device.rootURL)))
    }

    @Test
    func doesNotPlanTrashCleanupWithoutDeletes() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let planner = SyncPlanner(deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]))

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(!plan.actions.contains(.clearDeviceTrash(trashURL: device.trashURL)))
    }

    @Test
    func includesManuallySelectedDeviceFilesInDeletionPlan() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.musicURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let existingFileURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    managedDirectory.standardizedFileURL.path: [existingFileURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [subscription],
            manualDeleteTargets: [existingFileURL],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(plan.actions.contains(.deleteFromDevice(targetURL: existingFileURL)))
    }

    @Test
    func reusesExistingManagedFolderWhenSubscriptionTitlePunctuationChanges() throws {
        let device = makeDevice()
        let subscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Sean Carroll's Mindscape: Science, Society, Philosophy, Culture, Arts, and Ideas",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "2026.04.21-Episode 1-(Sean Carroll).mp3"
        )
        let actualDirectory = device.musicURL.appendingPathComponent(
            "Sean Carroll's Mindscape, Science, Society, Philosophy, Culture, Arts, and Ideas",
            isDirectory: true
        )
        let planner = SyncPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    actualDirectory.standardizedFileURL.path: []
                ],
                directoriesByDirectory: [
                    device.musicURL.standardizedFileURL.path: [actualDirectory]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            ejectAfterSync: false,
            isDryRun: true
        )

        #expect(plan.actions.contains(where: {
            guard case .copyToDevice(_, let destinationURL) = $0 else { return false }
            return destinationURL.deletingLastPathComponent().standardizedFileURL == actualDirectory.standardizedFileURL
        }))
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/WALKMAN/.Trashes", isDirectory: true)
        )
    }

    private func makeSubscription(retentionLimit: Int = 3) -> FeedSubscription {
        FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!,
            retentionPolicy: .keepLatestEpisodes(retentionLimit)
        )
    }

    private func makePreparedEpisode(id: String, title: String, preparedFileName: String) -> PreparedEpisode {
        let episode = Episode(
            id: id,
            subscriptionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            podcastTitle: "Example Podcast",
            title: title,
            publicationDate: Date(timeIntervalSince1970: TimeInterval(Int.random(in: 1...10))),
            enclosureURL: URL(string: "https://cdn.example.com/\(preparedFileName)")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        return PreparedEpisode(
            episode: episode,
            sourceFileURL: URL(fileURLWithPath: "/tmp/\(preparedFileName)", isDirectory: false),
            preparedFileURL: URL(fileURLWithPath: "/tmp/\(preparedFileName)", isDirectory: false),
            preparationAction: .passthroughMP3
        )
    }
}

private struct StubDeviceLibrary: DeviceLibraryInspecting {
    let filesByDirectory: [String: [URL]]
    let directoriesByDirectory: [String: [URL]]

    init(filesByDirectory: [String: [URL]], directoriesByDirectory: [String: [URL]] = [:]) {
        self.filesByDirectory = filesByDirectory
        self.directoriesByDirectory = directoriesByDirectory
    }

    func files(in directoryURL: URL) throws -> [URL] {
        filesByDirectory[directoryURL.standardizedFileURL.path] ?? []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        directoriesByDirectory[directoryURL.standardizedFileURL.path] ?? []
    }
}
