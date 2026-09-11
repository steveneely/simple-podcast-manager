import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct SafetyValidatorTests {
    @Test
    func validatesExpectedDeviceLayout() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: Never.self) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func validatesUppercasePodcastDirectoryLayout() throws {
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/MUSIC", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: Never.self) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func rejectsPodcastDirectoryOutsideDeviceRoot() throws {
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/OTHER/Podcasts", isDirectory: true)
        )
        let validator = SafetyValidator()

        #expect(throws: SafetyValidationError.invalidPodcastDirectory(URL(fileURLWithPath: "/Volumes/OTHER/Podcasts", isDirectory: true))) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func allowsConfiguredPodcastDirectoryInsideDeviceRoot() throws {
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/Podcasts", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: Never.self) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func allowsWritesInsideDevicePodcastDirectory() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let targetURL = URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/music/Accidental Tech Podcast/001.mp3")

        #expect(throws: Never.self) {
            try validator.validateWriteTarget(targetURL, on: device)
        }
    }

    @Test
    func rejectsWritesOutsideDevicePodcastDirectory() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let targetURL = URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/Documents/001.mp3")

        #expect(throws: SafetyValidationError.pathOutsideDevicePodcastDirectory(URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/Documents/001.mp3"))) {
            try validator.validateWriteTarget(targetURL, on: device)
        }
    }

    @Test
    func rejectsMacTrashTargets() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let targetURL = URL(fileURLWithPath: "/Users/tester/.Trash/episode.mp3")

        #expect(throws: SafetyValidationError.macTrashPathNotAllowed(URL(fileURLWithPath: "/Users/tester/.Trash/episode.mp3"))) {
            try validator.validateDeleteTarget(targetURL, on: device)
        }
    }

    @Test
    func allowsPlaylistOnlyAtConfiguredPlaylistDirectoryRoot() throws {
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/Podcast", isDirectory: true),
            playlistDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/playlist_data", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let playlistURL = device.playlistDirectoryURL.appendingPathComponent("Commute.m3u")

        #expect(throws: Never.self) {
            try validator.validatePodcastPlaylistTarget(playlistURL, on: device)
        }
        #expect(throws: SafetyValidationError.invalidPodcastPlaylistTarget(
            device.podcastDirectoryURL.appendingPathComponent("Commute.m3u")
        )) {
            try validator.validatePodcastPlaylistTarget(
                device.podcastDirectoryURL.appendingPathComponent("Commute.m3u"),
                on: device
            )
        }
    }

    @Test
    func allowsOwnedPlaylistDeletionFromPreviousFolderInsideDevice() throws {
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/Podcast", isDirectory: true),
            playlistDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/playlist_data", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let previousDirectoryURL = device.podcastDirectoryURL
        let playlistURL = previousDirectoryURL.appendingPathComponent("Commute.m3u")

        #expect(throws: Never.self) {
            try validator.validate(
                .deleteRelocatedPodcastPlaylist(
                    targetURL: playlistURL,
                    playlistDirectoryURL: previousDirectoryURL
                ),
                on: device
            )
        }
    }

    @Test
    func rejectsPreviousPlaylistFolderOutsideDevice() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let outsideDirectoryURL = URL(fileURLWithPath: "/Volumes/OTHER/playlist_data", isDirectory: true)
        let playlistURL = outsideDirectoryURL.appendingPathComponent("Commute.m3u")

        #expect(throws: SafetyValidationError.invalidPlaylistDirectory(outsideDirectoryURL)) {
            try validator.validate(
                .deleteRelocatedPodcastPlaylist(
                    targetURL: playlistURL,
                    playlistDirectoryURL: outsideDirectoryURL
                ),
                on: device
            )
        }
    }

    @Test
    func rejectsNestedOrNonM3UPlaylistTargets() {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let nestedURL = device.podcastDirectoryURL.appendingPathComponent("Lists/Commute.m3u")
        let wrongExtensionURL = device.podcastDirectoryURL.appendingPathComponent("Commute.txt")

        #expect(throws: SafetyValidationError.invalidPodcastPlaylistTarget(nestedURL)) {
            try validator.validatePodcastPlaylistTarget(nestedURL, on: device)
        }
        #expect(throws: SafetyValidationError.invalidPodcastPlaylistTarget(wrongExtensionURL)) {
            try validator.validatePodcastPlaylistTarget(wrongExtensionURL, on: device)
        }
    }

    @Test
    func rejectsDeviceRootsOutsideVolumes() throws {
        let device = DeviceInfo(
            name: "Temp Device",
            rootURL: URL(fileURLWithPath: "/tmp/TEST-MP3-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/tmp/TEST-MP3-PLAYER/music", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: SafetyValidationError.invalidDeviceRoot(URL(fileURLWithPath: "/tmp/TEST-MP3-PLAYER", isDirectory: true))) {
            try validator.validateDevice(device)
        }
    }

    private func makeDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-PLAYER/music", isDirectory: true)
        )
    }
}
