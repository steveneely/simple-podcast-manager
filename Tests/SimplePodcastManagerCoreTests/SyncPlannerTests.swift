import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SyncPlannerTests {
    @Test
    func plansCopyForPreparedEpisodeMissingFromDevice() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let planner = makeTestPlanner(deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]))

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false
        )

        #expect(
            plan.actions.contains(.copyToDevice(
                sourceURL: preparedEpisode.preparedFileURL,
                destinationURL: device.podcastDirectoryURL
                    .appendingPathComponent("Example Podcast", isDirectory: true)
                    .appendingPathComponent("Episode_1.mp3", isDirectory: false),
                fileSizeBytes: 1
            ))
        )
    }

    @Test
    func skipsCopyWhenDestinationAlreadyExists() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "2026.04.21-Episode 1-(Example Podcast).mp3"
        )
        let destinationURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("2026.04.21-Episode 1-(Example Podcast).mp3", isDirectory: false)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true).standardizedFileURL.path: [destinationURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false
        )

        #expect(plan.actions.contains(.skip(reason: "Already on device: Episode 1")))
        #expect(!plan.actions.contains(where: {
            if case .copyToDevice = $0 { return true }
            return false
        }))
    }

    @Test
    func skipsCopyWhenTransliteratedUnicodeFileAlreadyExists() throws {
        let device = makeDevice()
        let subscription = FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Hörspiel für große Hörer",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let episode = Episode(
            id: "unicode-episode",
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: "Die größte Folge",
            enclosureURL: URL(string: "https://example.com/unicode.mp3")!,
            sourceFeedURL: subscription.rssURL
        )
        let preparedFileURL = URL(
            fileURLWithPath: "/tmp/\(EpisodeFileName.fileName(for: episode, fileExtension: "mp3"))"
        )
        let preparedEpisode = PreparedEpisode(
            episode: episode,
            sourceFileURL: preparedFileURL,
            preparedFileURL: preparedFileURL,
            preparationAction: .passthroughMP3
        )
        let podcastDirectory = device.podcastDirectoryURL.appendingPathComponent(
            "Horspiel fur grosse Horer",
            isDirectory: true
        )
        let podcastFile = podcastDirectory.appendingPathComponent(preparedFileURL.lastPathComponent)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [podcastDirectory.path: [podcastFile]])
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            ejectAfterSync: false
        )

        #expect(plan.actions == [.skip(reason: "Already on device: Die größte Folge")])
    }

    @Test
    func appleDoubleSidecarDoesNotCountAsExistingEpisodeOnDevice() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "2026.04.21-Episode 1-(Example Podcast).mp3"
        )
        let sidecarURL = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
            .appendingPathComponent("._2026.04.21-Episode 1-(Example Podcast).mp3", isDirectory: false)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true).standardizedFileURL.path: [sidecarURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false
        )

        #expect(plan.actions.contains(where: {
            guard case .copyToDevice(_, let destinationURL, _) = $0 else { return false }
            return destinationURL.lastPathComponent == preparedEpisode.preparedFileURL.lastPathComponent
        }))
    }

    @Test
    func doesNotAutoDeleteManagedEpisodesWithoutManualSelection() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let preparedEpisodes = [
            makePreparedEpisode(id: "ep-3", title: "Episode 3", preparedFileName: "Episode_3.mp3"),
            makePreparedEpisode(id: "ep-2", title: "Episode 2", preparedFileName: "Episode_2.mp3"),
        ]
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let olderEpisodeURL = managedDirectory.appendingPathComponent("Episode_1.mp3", isDirectory: false)
        let currentEpisodeURL = managedDirectory.appendingPathComponent("Episode_2.mp3", isDirectory: false)
        let planner = makeTestPlanner(
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
            ejectAfterSync: false
        )

        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: olderEpisodeURL, fileSizeBytes: 1)))
        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: currentEpisodeURL, fileSizeBytes: 1)))
    }

    @Test
    func cleanupKeepsLatestEpisodesAcrossExistingAndIncomingFiles() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let firstEpisodeURL = managedDirectory.appendingPathComponent("2026.01.01-First Episode-(Example Podcast).mp3")
        let secondEpisodeURL = managedDirectory.appendingPathComponent("2026.01.02-Second Episode-(Example Podcast).mp3")
        let thirdEpisodeURL = managedDirectory.appendingPathComponent("2026.01.03-Third Episode-(Example Podcast).mp3")
        let fourthEpisodeURL = managedDirectory.appendingPathComponent("2026.01.04-Fourth Episode-(Example Podcast).mp3")
        let missingDateURL = managedDirectory.appendingPathComponent("Undated Episode-(Example Podcast).mp3")
        let unrelatedAudioURL = managedDirectory.appendingPathComponent("2026.01.01-Favorite Song.mp3")
        let preparedEpisodes = [
            makePreparedEpisode(
                id: "sixth",
                title: "Sixth Episode",
                preparedFileName: "2026.01.06-Sixth Episode-(Example Podcast).mp3"
            ),
            makePreparedEpisode(
                id: "fifth",
                title: "Fifth Episode",
                preparedFileName: "2026.01.05-Fifth Episode-(Example Podcast).mp3"
            ),
        ]
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    managedDirectory.path: [
                        firstEpisodeURL,
                        secondEpisodeURL,
                        thirdEpisodeURL,
                        fourthEpisodeURL,
                        missingDateURL,
                        unrelatedAudioURL,
                    ]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: preparedEpisodes,
            subscriptions: [subscription],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.map(\.targetURL) == [
            firstEpisodeURL,
            secondEpisodeURL,
            thirdEpisodeURL,
        ])
        #expect(plan.actions.filter { if case .deleteFromDevice = $0 { true } else { false } }.count == 3)
        #expect(!plan.cleanupCandidates.map(\.targetURL).contains(missingDateURL))
        #expect(!plan.cleanupCandidates.map(\.targetURL).contains(unrelatedAudioURL))
    }

    @Test
    func disabledCleanupDoesNotSuggestEpisodesBeyondAProspectiveLimit() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let oldEpisodeURL = managedDirectory.appendingPathComponent("2020.01.01-Old Episode-(Example Podcast).mp3")
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [oldEpisodeURL]])
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [makeSubscription()],
            cleanupPolicy: DeviceCleanupPolicy(),
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.isEmpty)
        #expect(plan.actions.isEmpty)
    }

    @Test
    func excludedCleanupCandidateRemainsVisibleButIsNotDeleted() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let oldEpisodeURL = managedDirectory.appendingPathComponent("2026.01.01-Old Episode-(Example Podcast).mp3")
        let newerEpisodeURLs = (2...4).map { day in
            managedDirectory.appendingPathComponent("2026.01.0\(day)-Episode \(day)-(Example Podcast).mp3")
        }
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [managedDirectory.path: [oldEpisodeURL] + newerEpisodeURLs]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [subscription],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            excludedCleanupTargets: [oldEpisodeURL],
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.map(\.targetURL) == [oldEpisodeURL])
        #expect(plan.actions.isEmpty)
    }

    @Test
    func selectedCleanupWinsWhenTheSameEpisodeIsStillPreparedLocally() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let fileName = "2026.01.01-Old Episode-(Example Podcast).mp3"
        let preparedEpisode = makePreparedEpisode(
            id: "old",
            title: "Old Episode",
            preparedFileName: fileName
        )
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let oldEpisodeURL = managedDirectory.appendingPathComponent(fileName)
        let newerEpisodeURLs = (2...4).map { day in
            managedDirectory.appendingPathComponent("2026.01.0\(day)-Episode \(day)-(Example Podcast).mp3")
        }
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [managedDirectory.path: [oldEpisodeURL] + newerEpisodeURLs]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            ejectAfterSync: false
        )

        #expect(plan.actions.contains(.deleteFromDevice(targetURL: oldEpisodeURL, fileSizeBytes: 1)))
        #expect(plan.actions.contains(.skip(reason: "Selected for removal from device: Old Episode")))
        #expect(!plan.actions.contains(.skip(reason: "Already on device: Old Episode")))
    }

    @Test
    func invalidEnabledCleanupPolicyFailsClosed() throws {
        let planner = makeTestPlanner(deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]))

        #expect(throws: DeviceCleanupPolicyError.invalidMaximumEpisodesPerShow(4)) {
            try planner.makePlan(
                device: makeDevice(),
                preparedEpisodes: [],
                subscriptions: [makeSubscription()],
                cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 4),
                ejectAfterSync: false
            )
        }
    }

    @Test
    func manualDeletionFreesARetentionSlotWithoutSelectingAnotherEpisode() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let episodeURLs = (1...4).map { day in
            managedDirectory.appendingPathComponent("2026.01.0\(day)-Episode \(day)-(Example Podcast).mp3")
        }
        let manuallyDeletedURL = episodeURLs[3]
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: episodeURLs])
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [makeSubscription()],
            manualDeleteTargets: [manuallyDeletedURL],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.isEmpty)
        #expect(plan.actions == [.deleteFromDevice(targetURL: manuallyDeletedURL, fileSizeBytes: 1)])
    }

    @Test
    func olderIncomingEpisodeIsCopiedWithoutDeletingARetainedDeviceEpisode() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let existingURLs = (2...4).map { day in
            managedDirectory.appendingPathComponent("2026.01.0\(day)-Episode \(day)-(Example Podcast).mp3")
        }
        let preparedEpisode = makePreparedEpisode(
            id: "older",
            title: "Older Episode",
            preparedFileName: "2026.01.01-Older Episode-(Example Podcast).mp3"
        )
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: existingURLs])
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.isEmpty)
        #expect(plan.actions.contains { if case .copyToDevice = $0 { true } else { false } })
    }

    @Test
    func cleanupKeepsEpisodesTiedOnTheRetentionBoundary() throws {
        let device = makeDevice()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let unambiguouslyOldURL = managedDirectory.appendingPathComponent(
            "2026.01.02-Old Episode-(Example Podcast).mp3"
        )
        let tiedURLs = ["Alpha", "Beta", "Gamma"].map { title in
            managedDirectory.appendingPathComponent(
                "2026.01.03-\(title)-(Example Podcast).mp3"
            )
        }
        let newestURL = managedDirectory.appendingPathComponent(
            "2026.01.04-New Episode-(Example Podcast).mp3"
        )
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [managedDirectory.path: [unambiguouslyOldURL] + tiedURLs + [newestURL]]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [makeSubscription()],
            cleanupPolicy: DeviceCleanupPolicy(maximumEpisodesPerShow: 3),
            ejectAfterSync: false
        )

        #expect(plan.cleanupCandidates.map(\.targetURL) == [unambiguouslyOldURL])
        #expect(tiedURLs.allSatisfy { tiedURL in
            !plan.actions.contains(.deleteFromDevice(targetURL: tiedURL, fileSizeBytes: 1))
        })
    }

    @Test
    func doesNotDeleteFilesOutsideManagedPodcastFolders() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let unmanagedFileURL = device.podcastDirectoryURL.appendingPathComponent("random_track.mp3", isDirectory: false)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.standardizedFileURL.path: [unmanagedFileURL]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false
        )

        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: unmanagedFileURL, fileSizeBytes: 1)))
    }

    @Test
    func plansDirectDeleteAndOptionalEject() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let existingFileURL = managedDirectory.appendingPathComponent("2026.04.21-Episode 1-(Example Podcast).mp3", isDirectory: false)
        let planner = makeTestPlanner(
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
            ejectAfterSync: true
        )

        #expect(plan.actions.contains(.deleteFromDevice(targetURL: existingFileURL, fileSizeBytes: 1)))
        #expect(plan.actions.contains(.ejectDevice(deviceRootURL: device.rootURL)))
    }

    @Test
    func ignoresManuallySelectedFilesThatAreNotManagedEpisodes() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let unmanagedFileURL = managedDirectory.appendingPathComponent("notes.txt", isDirectory: false)
        let unrelatedAudioURL = managedDirectory.appendingPathComponent("Favorite Song.mp3", isDirectory: false)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    managedDirectory.standardizedFileURL.path: [
                        unmanagedFileURL,
                        unrelatedAudioURL,
                    ]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: [subscription],
            manualDeleteTargets: [unmanagedFileURL, unrelatedAudioURL],
            ejectAfterSync: false
        )

        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: unmanagedFileURL, fileSizeBytes: 1)))
        #expect(!plan.actions.contains(.deleteFromDevice(targetURL: unrelatedAudioURL, fileSizeBytes: 1)))
    }

    @Test
    func doesNotPlanDeleteWithoutManualSelection() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "ep-1",
            title: "Episode 1",
            preparedFileName: "Episode_1.mp3"
        )
        let planner = makeTestPlanner(deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]))

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            ejectAfterSync: false
        )

        #expect(!plan.actions.contains(where: {
            if case .deleteFromDevice = $0 { return true }
            return false
        }))
    }

    @Test
    func includesManuallySelectedDeviceFilesInDeletionPlan() throws {
        let device = makeDevice()
        let subscription = makeSubscription()
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("Example Podcast", isDirectory: true)
        let existingFileURL = managedDirectory.appendingPathComponent("2026.04.21-Episode 1-(Example Podcast).mp3", isDirectory: false)
        let planner = makeTestPlanner(
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
            ejectAfterSync: false
        )

        #expect(plan.actions.contains(.deleteFromDevice(targetURL: existingFileURL, fileSizeBytes: 1)))
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
        let actualDirectory = device.podcastDirectoryURL.appendingPathComponent(
            "Sean Carroll's Mindscape, Science, Society, Philosophy, Culture, Arts, and Ideas",
            isDirectory: true
        )
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    actualDirectory.standardizedFileURL.path: []
                ],
                directoriesByDirectory: [
                    device.podcastDirectoryURL.standardizedFileURL.path: [actualDirectory]
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [subscription],
            ejectAfterSync: false
        )

        #expect(plan.actions.contains(where: {
            guard case .copyToDevice(_, let destinationURL, _) = $0 else { return false }
            return destinationURL.deletingLastPathComponent().standardizedFileURL == actualDirectory.standardizedFileURL
        }))
    }

    @Test
    func enumeratesDeviceDirectoriesOnceWhenPlanningMultipleSubscriptions() throws {
        let device = makeDevice()
        let subscriptions = [
            FeedSubscription(title: "First", rssURL: URL(string: "https://example.com/first.xml")!),
            FeedSubscription(title: "Second", rssURL: URL(string: "https://example.com/second.xml")!),
        ]
        let deviceLibrary = CountingPlannerDeviceLibrary()
        let planner = makeTestPlanner(deviceLibrary: deviceLibrary)

        _ = try planner.makePlan(
            device: device,
            preparedEpisodes: [],
            subscriptions: subscriptions,
            ejectAfterSync: false
        )

        #expect(deviceLibrary.directoryRequestCount == 1)
        #expect(deviceLibrary.recursiveFileRequestCount == 0)
        #expect(deviceLibrary.directFileRequestCount == 2)
    }

    @Test
    func putsSelectedDeletionsBeforeCopiesWhenSpaceIsAlreadyAvailable() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "new",
            title: "New Episode",
            preparedFileName: "2026.07.18-New Episode-(Example Podcast).mp3"
        )
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteURL = managedDirectory
            .appendingPathComponent("2026.07.01-Old Episode-(Example Podcast).mp3")
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [deleteURL]]),
            storageInspector: TestSyncStorageInspector(
                availableBytes: 200,
                sizesByPath: [
                    preparedEpisode.preparedFileURL.path: 100,
                    deleteURL.path: 60,
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            manualDeleteTargets: [deleteURL],
            ejectAfterSync: false
        )

        #expect(plan.actions.count == 2)
        #expect(plan.actions[0] == .deleteFromDevice(targetURL: deleteURL, fileSizeBytes: 60))
        #expect({ if case .copyToDevice = plan.actions[1] { true } else { false } }())
    }

    @Test
    func reportsTotalCopySizeWhenTheCompletePlanDoesNotFit() throws {
        let device = makeDevice()
        let firstEpisode = makePreparedEpisode(
            id: "first",
            title: "First Episode",
            preparedFileName: "First Episode.mp3"
        )
        let secondEpisode = makePreparedEpisode(
            id: "second",
            title: "Second Episode",
            preparedFileName: "Second Episode.mp3"
        )
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [:]),
            storageInspector: TestSyncStorageInspector(
                availableBytes: 100,
                sizesByPath: [
                    firstEpisode.preparedFileURL.path: 70,
                    secondEpisode.preparedFileURL.path: 80,
                ]
            )
        )

        #expect(throws: SyncCapacityError.insufficientCapacity(
            requiredBytes: 150,
            availableBytes: 100
        )) {
            try planner.makePlan(
                device: device,
                preparedEpisodes: [firstEpisode, secondEpisode],
                subscriptions: [makeSubscription()],
                ejectAfterSync: false
            )
        }
    }

    @Test
    func putsSelectedDeletionBeforeCopyWhenDeletionMakesTheSyncFit() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "new",
            title: "New Episode",
            preparedFileName: "2026.07.18-New Episode-(Example Podcast).mp3"
        )
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteURL = managedDirectory
            .appendingPathComponent("2026.07.01-Old Episode-(Example Podcast).mp3")
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [deleteURL]]),
            storageInspector: TestSyncStorageInspector(
                availableBytes: 50,
                sizesByPath: [
                    preparedEpisode.preparedFileURL.path: 100,
                    deleteURL.path: 60,
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            manualDeleteTargets: [deleteURL],
            ejectAfterSync: false
        )

        #expect(plan.actions[0] == .deleteFromDevice(targetURL: deleteURL, fileSizeBytes: 60))
        #expect({ if case .copyToDevice = plan.actions[1] { true } else { false } }())
    }

    @Test
    func rejectsPlanWhenSelectedDeletionsStillDoNotMakeEnoughSpace() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "new",
            title: "New Episode",
            preparedFileName: "2026.07.18-New Episode-(Example Podcast).mp3"
        )
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let deleteURL = managedDirectory
            .appendingPathComponent("2026.07.01-Old Episode-(Example Podcast).mp3")
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [deleteURL]]),
            storageInspector: TestSyncStorageInspector(
                availableBytes: 50,
                sizesByPath: [
                    preparedEpisode.preparedFileURL.path: 100,
                    deleteURL.path: 40,
                ]
            )
        )

        #expect(throws: SyncCapacityError.insufficientCapacity(
            requiredBytes: 100,
            availableBytes: 90
        )) {
            try planner.makePlan(
                device: device,
                preparedEpisodes: [preparedEpisode],
                subscriptions: [makeSubscription()],
                manualDeleteTargets: [deleteURL],
                ejectAfterSync: false
            )
        }
    }

    @Test
    func reportsExistingDestinationWithUnexpectedSizeAsIncomplete() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "new",
            title: "New Episode",
            preparedFileName: "2026.07.18-New Episode-(Example Podcast).mp3"
        )
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let destinationURL = managedDirectory
            .appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [destinationURL]]),
            storageInspector: TestSyncStorageInspector(
                sizesByPath: [
                    preparedEpisode.preparedFileURL.path: 100,
                    destinationURL.path: 25,
                ]
            )
        )

        #expect(throws: SyncCapacityError.incompleteExistingCopy(
            targetURL: destinationURL,
            expectedBytes: 100,
            actualBytes: 25
        )) {
            try planner.makePlan(
                device: device,
                preparedEpisodes: [preparedEpisode],
                subscriptions: [makeSubscription()],
                ejectAfterSync: false
            )
        }
    }

    @Test
    func plansDeleteThenCopyWhenReplacingAnIncompleteDeviceCopy() throws {
        let device = makeDevice()
        let preparedEpisode = makePreparedEpisode(
            id: "new",
            title: "New Episode",
            preparedFileName: "2026.07.18-New Episode-(Example Podcast).mp3"
        )
        let managedDirectory = device.podcastDirectoryURL
            .appendingPathComponent("Example Podcast", isDirectory: true)
        let destinationURL = managedDirectory
            .appendingPathComponent(preparedEpisode.preparedFileURL.lastPathComponent)
        let planner = makeTestPlanner(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory.path: [destinationURL]]),
            storageInspector: TestSyncStorageInspector(
                sizesByPath: [
                    preparedEpisode.preparedFileURL.path: 100,
                    destinationURL.path: 25,
                ]
            )
        )

        let plan = try planner.makePlan(
            device: device,
            preparedEpisodes: [preparedEpisode],
            subscriptions: [makeSubscription()],
            replacementTargets: [destinationURL],
            ejectAfterSync: false
        )

        #expect(plan.actions == [
            .deleteFromDevice(targetURL: destinationURL, fileSizeBytes: 25),
            .copyToDevice(
                sourceURL: preparedEpisode.preparedFileURL,
                destinationURL: destinationURL,
                fileSizeBytes: 100
            ),
        ])
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "SPM Test Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true)
        )
    }

    private func makeSubscription() -> FeedSubscription {
        FeedSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Example Podcast",
            rssURL: URL(string: "https://example.com/feed.xml")!
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
        let directoryPath = directoryURL.standardizedFileURL.path
        if let directories = directoriesByDirectory[directoryPath] {
            return directories
        }
        return filesByDirectory.keys.compactMap { path in
            let childURL = URL(fileURLWithPath: path, isDirectory: true)
            return childURL.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL
                ? childURL
                : nil
        }
    }
}

private final class CountingPlannerDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
    private(set) var directoryRequestCount = 0
    private(set) var recursiveFileRequestCount = 0
    private(set) var directFileRequestCount = 0

    func files(in directoryURL: URL) throws -> [URL] {
        directFileRequestCount += 1
        return []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        directoryRequestCount += 1
        return []
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        recursiveFileRequestCount += 1
        return []
    }
}
