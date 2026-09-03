import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct DeviceLibraryViewModelTests {
    @Test
    func matchesCurrentEpisodesAndKeepsOlderDeviceFilesSeparate() async throws {
        let subscription = FeedSubscription(
            title: "Connected",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let episode = Episode(
            id: "current-episode",
            subscriptionID: subscription.id,
            podcastTitle: subscription.title,
            title: "Current Episode",
            publicationDate: Date(timeIntervalSince1970: 1_777_000_000),
            enclosureURL: URL(string: "https://example.com/current.mp3")!,
            sourceFeedURL: subscription.rssURL
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let subscriptionDirectory = device.podcastDirectoryURL.appendingPathComponent(subscription.title, isDirectory: true)
        let currentEpisodeFile = subscriptionDirectory.appendingPathComponent(
            EpisodeFileName.fileName(for: episode, fileExtension: "mp3")
        )
        let olderEpisodeFile = subscriptionDirectory.appendingPathComponent(
            "2025.01.01-Older Episode-(Connected).mp3"
        )
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    subscriptionDirectory: [olderEpisodeFile, currentEpisodeFile]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.file(for: episode) == currentEpisodeFile)
        #expect(viewModel.unmatchedFiles(for: subscription, episodes: [episode]) == [olderEpisodeFile])
    }

    @Test
    func associatesTransliteratedUnicodeFilesWithTheirPodcast() async throws {
        let subscription = FeedSubscription(
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
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let podcastDirectory = device.podcastDirectoryURL.appendingPathComponent(
            "Horspiel fur grosse Horer",
            isDirectory: true
        )
        let podcastFile = podcastDirectory.appendingPathComponent(
            "Die grosste Folge-(Horspiel fur grosse Horer).mp3"
        )
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [podcastDirectory: [podcastFile]])
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [podcastFile])
        #expect(viewModel.file(for: episode) == podcastFile)
        #expect(viewModel.otherAudioFiles.isEmpty)
    }

    @Test
    func refreshOrdersDeviceFilesNewestToOldestWhenEpisodesMatch() async throws {
        let subscription = FeedSubscription(
            title: "Connected",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let oldFile = device.podcastDirectoryURL.appendingPathComponent("Connected/2026.04.20-Old Episode-(Connected).mp3")
        let newFile = device.podcastDirectoryURL.appendingPathComponent("Connected/2026.04.21-New Episode-(Connected).mp3")
        let unmatchedFile = device.podcastDirectoryURL.appendingPathComponent("Connected/Bonus Clip.mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("Connected", isDirectory: true): [
                        unmatchedFile,
                        oldFile,
                        newFile,
                    ]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [newFile, oldFile])
    }

    @Test
    func refreshFallsBackToFileNameOrderingWhenEpisodesDoNotMatch() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let alphaFile = device.podcastDirectoryURL.appendingPathComponent("ATP/Alpha.mp3")
        let zuluFile = device.podcastDirectoryURL.appendingPathComponent("ATP/Zulu.mp3")
        let alphaManagedFile = device.podcastDirectoryURL.appendingPathComponent("ATP/Alpha-(ATP).mp3")
        let zuluManagedFile = device.podcastDirectoryURL.appendingPathComponent("ATP/Zulu-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true): [
                        zuluManagedFile,
                        zuluFile,
                        alphaManagedFile,
                        alphaFile,
                    ]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [alphaManagedFile, zuluManagedFile])
    }

    @Test
    func refreshIgnoresAppleDoubleMetadataSidecars() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let realFile = device.podcastDirectoryURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let sidecarFile = device.podcastDirectoryURL.appendingPathComponent("ATP/._2026.04.21-Episode-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true): [
                        sidecarFile,
                        realFile,
                    ]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [realFile])
    }

    @Test
    func refreshIgnoresFilesThatDoNotLookAppManaged() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedFile = device.podcastDirectoryURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let unrelatedAudioFile = device.podcastDirectoryURL.appendingPathComponent("ATP/Favorite Song.mp3")
        let noteFile = device.podcastDirectoryURL.appendingPathComponent("ATP/notes.txt")
        let otherPodcastFile = device.podcastDirectoryURL.appendingPathComponent("ATP/2026.04.21-Episode-(Other Podcast).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true): [
                        managedFile,
                        unrelatedAudioFile,
                        noteFile,
                        otherPodcastFile,
                    ]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [managedFile])
    }

    @Test
    func refreshUsesExistingManagedFolderWhenSubscriptionTitlePunctuationChanges() async throws {
        let subscription = FeedSubscription(
            title: "Sean Carroll's Mindscape: Science, Society, Philosophy, Culture, Arts, and Ideas",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let actualDirectory = device.podcastDirectoryURL.appendingPathComponent(
            "Sean Carroll's Mindscape, Science, Society, Philosophy, Culture, Arts, and Ideas",
            isDirectory: true
        )
        let episodeFile = actualDirectory.appendingPathComponent(
            "2026.04.20-351 | Peter Singer on Maximizing Good for All Sentient Creatures-(Sean Carroll).mp3"
        )
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    actualDirectory: [episodeFile]
                ],
                directoriesByDirectory: [
                    device.podcastDirectoryURL: [actualDirectory]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [episodeFile])
    }

    @Test
    func refreshShowsOtherAudioFilesNotAssociatedWithSubscriptions() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedFile = device.podcastDirectoryURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let otherPodcastFile = device.podcastDirectoryURL.appendingPathComponent("Old Podcast/random.mp3")
        let musicFile = device.podcastDirectoryURL.appendingPathComponent("Album/song.m4a")
        let sidecarFile = device.podcastDirectoryURL.appendingPathComponent("Album/._song.m4a")
        let noteFile = device.podcastDirectoryURL.appendingPathComponent("Album/notes.txt")
        let atpDirectory = device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true)
        let oldPodcastDirectory = device.podcastDirectoryURL.appendingPathComponent("Old Podcast", isDirectory: true)
        let albumDirectory = device.podcastDirectoryURL.appendingPathComponent("Album", isDirectory: true)
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    atpDirectory: [managedFile],
                    oldPodcastDirectory: [otherPodcastFile],
                    albumDirectory: [musicFile, sidecarFile, noteFile],
                ],
                directoriesByDirectory: [
                    device.podcastDirectoryURL: [atpDirectory, oldPodcastDirectory, albumDirectory]
                ]
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [managedFile])
        #expect(viewModel.otherAudioFiles.isEmpty)
        #expect(viewModel.hasOtherAudioAvailable)

        await viewModel.reviewOtherAudio(on: device)

        #expect(viewModel.otherAudioFiles == [musicFile, otherPodcastFile])
    }

    @Test
    func matchingFileNameInAnUnrelatedFolderRemainsOtherAudio() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let unrelatedDirectory = device.podcastDirectoryURL.appendingPathComponent("Archive", isDirectory: true)
        let unrelatedFile = unrelatedDirectory.appendingPathComponent("Old Recording-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [unrelatedDirectory: [unrelatedFile]])
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription).isEmpty)
        #expect(viewModel.otherAudioFiles.isEmpty)

        await viewModel.reviewOtherAudio(on: device)

        #expect(viewModel.otherAudioFiles == [unrelatedFile])
    }

    @Test
    func deleteOtherAudioFilesOnlyDeletesExplicitKnownOtherAudioUnderDevicePodcastDirectory() async throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedFile = device.podcastDirectoryURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let otherFile = device.podcastDirectoryURL.appendingPathComponent("Old Podcast/random.mp3")
        let otherSidecar = device.podcastDirectoryURL.appendingPathComponent("Old Podcast/._random.mp3")
        let unknownFile = device.podcastDirectoryURL.appendingPathComponent("Unknown/other.mp3")
        let atpDirectory = device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true)
        let oldPodcastDirectory = device.podcastDirectoryURL.appendingPathComponent("Old Podcast", isDirectory: true)
        let fileSystem = CapturingFileSystem(existingFiles: [otherSidecar])
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    atpDirectory: [managedFile],
                    oldPodcastDirectory: [otherFile],
                ],
                directoriesByDirectory: [
                    device.podcastDirectoryURL: [atpDirectory, oldPodcastDirectory]
                ]
            ),
            fileSystem: fileSystem
        )
        await viewModel.refresh(device: device, subscriptions: [subscription])
        await viewModel.reviewOtherAudio(on: device)

        viewModel.deleteOtherAudioFiles([otherFile.standardizedFileURL, unknownFile.standardizedFileURL], on: device)

        #expect(fileSystem.removedItems == [otherFile.standardizedFileURL, otherSidecar.standardizedFileURL])
        #expect(viewModel.otherAudioFiles.isEmpty)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test
    func refreshInventoriesDeviceFilesOnceForMultipleSubscriptions() async throws {
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let subscriptions = [
            FeedSubscription(title: "First", rssURL: URL(string: "https://example.com/first.xml")!),
            FeedSubscription(title: "Second", rssURL: URL(string: "https://example.com/second.xml")!),
        ]
        let directories = subscriptions.map {
            device.podcastDirectoryURL.appendingPathComponent($0.title, isDirectory: true)
        }
        let files = zip(subscriptions, directories).map { subscription, directory in
            directory.appendingPathComponent("2026.04.21-Episode-(\(subscription.title)).mp3")
        }
        let deviceLibrary = CountingDeviceLibrary(
            directories: directories,
            filesByDirectory: Dictionary(uniqueKeysWithValues: zip(directories, files.map { [$0] }))
        )
        let viewModel = DeviceLibraryViewModel(deviceLibrary: deviceLibrary)

        await viewModel.refresh(device: device, subscriptions: subscriptions)

        #expect(deviceLibrary.directoryRequestCount == 1)
        #expect(deviceLibrary.recursiveFileRequestCount == 0)
        #expect(deviceLibrary.audioPresenceRequestCount == 1)
        #expect(deviceLibrary.directFileRequestCount == 2)
        #expect(viewModel.files(for: subscriptions[0]) == [files[0]])
        #expect(viewModel.files(for: subscriptions[1]) == [files[1]])
    }

    @Test
    func normalRefreshDoesNotRecursivelyEnumerateVirtualLargeLibrary() async {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let deviceLibrary = VirtualLargeDeviceLibrary(unrelatedFileCount: 12_000)
        let viewModel = DeviceLibraryViewModel(deviceLibrary: deviceLibrary)

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(deviceLibrary.unrelatedFileCount == 12_000)
        #expect(deviceLibrary.directoryRequestCount == 1)
        #expect(deviceLibrary.directFileRequestCount == 1)
        #expect(deviceLibrary.recursiveFileRequestCount == 0)
        #expect(deviceLibrary.audioPresenceRequestCount == 1)
        #expect(viewModel.otherAudioFiles.isEmpty)
        #expect(!viewModel.hasOtherAudio)
        #expect(viewModel.hasOtherAudioAvailable)
    }

    @Test
    func otherAudioReviewKeepsSectionEmptyWhenDeviceContainsOnlyManagedFiles() async {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true)
        let managedFile = managedDirectory.appendingPathComponent("2026.04.21-Episode-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(filesByDirectory: [managedDirectory: [managedFile]])
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])
        #expect(!viewModel.hasOtherAudioAvailable)
        await viewModel.reviewOtherAudio(on: device)

        #expect(viewModel.otherAudioFiles.isEmpty)
        #expect(!viewModel.hasOtherAudio)
        #expect(viewModel.otherAudioReviewMessage == "No other audio found.")
    }

    @Test
    func failedOptionalAudioPresenceProbeDoesNotBlockManagedInventory() async {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedDirectory = device.podcastDirectoryURL.appendingPathComponent("ATP", isDirectory: true)
        let managedFile = managedDirectory.appendingPathComponent("2026.04.21-Episode-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: AudioPresenceFailingDeviceLibrary(
                managedDirectory: managedDirectory,
                managedFile: managedFile
            )
        )

        await viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [managedFile])
        #expect(!viewModel.hasOtherAudioAvailable)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test
    func dismissingOtherAudioResultsHidesTheCompletedReview() async {
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let otherFile = device.podcastDirectoryURL.appendingPathComponent("Album/song.mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.podcastDirectoryURL.appendingPathComponent("Album", isDirectory: true): [otherFile]
                ]
            )
        )
        await viewModel.refresh(device: device, subscriptions: [])
        await viewModel.reviewOtherAudio(on: device)
        #expect(viewModel.hasOtherAudio)

        viewModel.dismissOtherAudioResults()

        #expect(!viewModel.hasOtherAudio)
        #expect(viewModel.otherAudioFiles.isEmpty)
        #expect(viewModel.otherAudioReviewMessage == nil)
    }

    @Test
    func cancellingOtherAudioReviewStopsTheRecursiveScan() async {
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let deviceLibrary = CancellationAwareDeviceLibrary()
        let viewModel = DeviceLibraryViewModel(deviceLibrary: deviceLibrary)
        await viewModel.refresh(device: device, subscriptions: [])

        let reviewTask = Task {
            await viewModel.reviewOtherAudio(on: device)
        }
        for _ in 0..<1_000 where !deviceLibrary.hasStartedRecursiveScan {
            await Task.yield()
        }
        #expect(deviceLibrary.hasStartedRecursiveScan)

        viewModel.cancelOtherAudioReview()
        await reviewTask.value

        #expect(deviceLibrary.observedCancellation)
        #expect(!viewModel.isReviewingOtherAudio)
        #expect(viewModel.otherAudioFiles.isEmpty)
    }

    @Test
    func refreshInventoriesDeviceOutsideMainThread() async {
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let deviceLibrary = ThreadCapturingDeviceLibrary()
        let viewModel = DeviceLibraryViewModel(deviceLibrary: deviceLibrary)

        await viewModel.refresh(device: device, subscriptions: [])

        #expect(deviceLibrary.allRequestsWereOffMainThread)
    }
}

private struct StubDeviceLibrary: DeviceLibraryInspecting {
    let filesByDirectory: [URL: [URL]]
    let directoriesByDirectory: [URL: [URL]]

    init(filesByDirectory: [URL: [URL]], directoriesByDirectory: [URL: [URL]] = [:]) {
        self.filesByDirectory = filesByDirectory
        self.directoriesByDirectory = directoriesByDirectory
    }

    func files(in directoryURL: URL) throws -> [URL] {
        filesByDirectory[directoryURL] ?? []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        if let directories = directoriesByDirectory[directoryURL] {
            return directories
        }
        return filesByDirectory.keys.filter {
            $0.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL
        }
    }
}

private final class CountingDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
    let directoryURLs: [URL]
    let filesByDirectory: [URL: [URL]]
    private(set) var directoryRequestCount = 0
    private(set) var recursiveFileRequestCount = 0
    private(set) var directFileRequestCount = 0
    private(set) var audioPresenceRequestCount = 0

    init(directories: [URL], filesByDirectory: [URL: [URL]]) {
        self.directoryURLs = directories
        self.filesByDirectory = filesByDirectory
    }

    func files(in directoryURL: URL) throws -> [URL] {
        directFileRequestCount += 1
        return filesByDirectory[directoryURL] ?? []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        directoryRequestCount += 1
        return directoryURLs
    }

    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool {
        audioPresenceRequestCount += 1
        let excludedFileURLs = Set(fileURLs.map(\.standardizedFileURL))
        return filesByDirectory.values.joined().contains {
            DeviceAudioFile.isSupported($0)
                && !excludedFileURLs.contains($0.standardizedFileURL)
        }
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        recursiveFileRequestCount += 1
        return filesByDirectory.values.flatMap { $0 }
    }
}

private final class VirtualLargeDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
    let unrelatedFileCount: Int
    private(set) var directoryRequestCount = 0
    private(set) var recursiveFileRequestCount = 0
    private(set) var directFileRequestCount = 0
    private(set) var audioPresenceRequestCount = 0

    init(unrelatedFileCount: Int) {
        self.unrelatedFileCount = unrelatedFileCount
    }

    func files(in directoryURL: URL) throws -> [URL] {
        directFileRequestCount += 1
        return []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        directoryRequestCount += 1
        return []
    }

    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool {
        audioPresenceRequestCount += 1
        return unrelatedFileCount > 0
    }

    func recursiveFiles(in directoryURL: URL) throws -> [URL] {
        recursiveFileRequestCount += 1
        return []
    }
}

private final class CancellationAwareDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var startedRecursiveScan = false
    private var cancellationWasObserved = false

    var hasStartedRecursiveScan: Bool {
        lock.withLock { startedRecursiveScan }
    }

    var observedCancellation: Bool {
        lock.withLock { cancellationWasObserved }
    }

    func files(in directoryURL: URL) throws -> [URL] {
        []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        []
    }

    func recursiveFiles(
        in directoryURL: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [URL] {
        lock.withLock { startedRecursiveScan = true }
        while !Task.isCancelled {
            Thread.sleep(forTimeInterval: 0.000_1)
        }
        lock.withLock { cancellationWasObserved = true }
        throw CancellationError()
    }
}

private struct AudioPresenceFailingDeviceLibrary: DeviceLibraryInspecting {
    let managedDirectory: URL
    let managedFile: URL

    func files(in directoryURL: URL) throws -> [URL] {
        directoryURL.standardizedFileURL == managedDirectory.standardizedFileURL ? [managedFile] : []
    }

    func directories(in directoryURL: URL) throws -> [URL] {
        [managedDirectory]
    }

    func containsSupportedAudioFile(in directoryURL: URL, excluding fileURLs: Set<URL>) throws -> Bool {
        throw CocoaError(.fileReadNoPermission)
    }
}

private final class ThreadCapturingDeviceLibrary: DeviceLibraryInspecting, @unchecked Sendable {
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

private final class CapturingFileSystem: FileSystemOperating, @unchecked Sendable {
    private let existingFiles: Set<URL>
    private(set) var removedItems: [URL] = []

    init(existingFiles: Set<URL> = []) {
        self.existingFiles = Set(existingFiles.map(\.standardizedFileURL))
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url.standardizedFileURL)
    }

    func createDirectory(at url: URL) throws {}

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {}

    func removeItem(at url: URL) throws {
        removedItems.append(url.standardizedFileURL)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        []
    }
}
