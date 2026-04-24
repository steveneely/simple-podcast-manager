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
    func validatesUppercaseMusicDirectoryLayout() throws {
        let device = DeviceInfo(
            name: "Sony Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/MUSIC", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: Never.self) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func rejectsMusicDirectoryOutsideDeviceRoot() throws {
        let device = DeviceInfo(
            name: "Sony Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/Podcasts", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes", isDirectory: true)
        )
        let validator = SafetyValidator()

        #expect(throws: SafetyValidationError.invalidMusicDirectory(expected: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true), actual: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/Podcasts", isDirectory: true))) {
            try validator.validateDevice(device)
        }
    }

    @Test
    func allowsWritesInsideDeviceMusic() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let targetURL = URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music/Accidental Tech Podcast/001.mp3")

        #expect(throws: Never.self) {
            try validator.validateWriteTarget(targetURL, on: device)
        }
    }

    @Test
    func rejectsWritesOutsideDeviceMusic() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let targetURL = URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/Documents/001.mp3")

        #expect(throws: SafetyValidationError.pathOutsideDeviceMusic(URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/Documents/001.mp3"))) {
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
    func onlyAllowsClearingExactDeviceTrashDirectory() throws {
        let device = makeDeviceInfo()
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: Never.self) {
            try validator.validateClearTrashTarget(device.trashURL, on: device)
        }

        #expect(throws: SafetyValidationError.clearTrashRequiresExactDeviceTrash(URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes/subdir", isDirectory: true))) {
            try validator.validateClearTrashTarget(
                URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes/subdir", isDirectory: true),
                on: device
            )
        }
    }

    @Test
    func rejectsDeviceRootsOutsideVolumes() throws {
        let device = DeviceInfo(
            name: "Temp Device",
            rootURL: URL(fileURLWithPath: "/tmp/WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/tmp/WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/tmp/WALKMAN/.Trashes", isDirectory: true)
        )
        let validator = SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))

        #expect(throws: SafetyValidationError.invalidDeviceRoot(URL(fileURLWithPath: "/tmp/WALKMAN", isDirectory: true))) {
            try validator.validateDevice(device)
        }
    }

    private func makeDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            name: "Sony Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN", isDirectory: true),
            musicURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/music", isDirectory: true),
            trashURL: URL(fileURLWithPath: "/Volumes/SPM-TEST-WALKMAN/.Trashes", isDirectory: true)
        )
    }
}
