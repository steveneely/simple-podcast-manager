import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct DeviceLibraryViewModelTests {
    @Test
    func refreshOrdersDeviceFilesNewestToOldestWhenEpisodesMatch() throws {
        let subscription = FeedSubscription(
            title: "Connected",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let oldFile = device.musicURL.appendingPathComponent("Connected/2026.04.20-Old Episode-(Connected).mp3")
        let newFile = device.musicURL.appendingPathComponent("Connected/2026.04.21-New Episode-(Connected).mp3")
        let unmatchedFile = device.musicURL.appendingPathComponent("Connected/Bonus Clip.mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("Connected", isDirectory: true): [
                        unmatchedFile,
                        oldFile,
                        newFile,
                    ]
                ]
            )
        )

        viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [newFile, oldFile])
    }

    @Test
    func refreshFallsBackToFileNameOrderingWhenEpisodesDoNotMatch() throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let alphaFile = device.musicURL.appendingPathComponent("ATP/Alpha.mp3")
        let zuluFile = device.musicURL.appendingPathComponent("ATP/Zulu.mp3")
        let alphaManagedFile = device.musicURL.appendingPathComponent("ATP/Alpha-(ATP).mp3")
        let zuluManagedFile = device.musicURL.appendingPathComponent("ATP/Zulu-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("ATP", isDirectory: true): [
                        zuluManagedFile,
                        zuluFile,
                        alphaManagedFile,
                        alphaFile,
                    ]
                ]
            )
        )

        viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [alphaManagedFile, zuluManagedFile])
    }

    @Test
    func refreshIgnoresAppleDoubleMetadataSidecars() throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let realFile = device.musicURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let sidecarFile = device.musicURL.appendingPathComponent("ATP/._2026.04.21-Episode-(ATP).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("ATP", isDirectory: true): [
                        sidecarFile,
                        realFile,
                    ]
                ]
            )
        )

        viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [realFile])
    }

    @Test
    func refreshIgnoresFilesThatDoNotLookAppManaged() throws {
        let subscription = FeedSubscription(
            title: "ATP",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let managedFile = device.musicURL.appendingPathComponent("ATP/2026.04.21-Episode-(ATP).mp3")
        let unrelatedAudioFile = device.musicURL.appendingPathComponent("ATP/Favorite Song.mp3")
        let noteFile = device.musicURL.appendingPathComponent("ATP/notes.txt")
        let otherPodcastFile = device.musicURL.appendingPathComponent("ATP/2026.04.21-Episode-(Other Podcast).mp3")
        let viewModel = DeviceLibraryViewModel(
            deviceLibrary: StubDeviceLibrary(
                filesByDirectory: [
                    device.musicURL.appendingPathComponent("ATP", isDirectory: true): [
                        managedFile,
                        unrelatedAudioFile,
                        noteFile,
                        otherPodcastFile,
                    ]
                ]
            )
        )

        viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [managedFile])
    }

    @Test
    func refreshUsesExistingManagedFolderWhenSubscriptionTitlePunctuationChanges() throws {
        let subscription = FeedSubscription(
            title: "Sean Carroll's Mindscape: Science, Society, Philosophy, Culture, Arts, and Ideas",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let device = DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )
        let actualDirectory = device.musicURL.appendingPathComponent(
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
                    device.musicURL: [actualDirectory]
                ]
            )
        )

        viewModel.refresh(device: device, subscriptions: [subscription])

        #expect(viewModel.files(for: subscription) == [episodeFile])
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
        directoriesByDirectory[directoryURL] ?? []
    }
}
