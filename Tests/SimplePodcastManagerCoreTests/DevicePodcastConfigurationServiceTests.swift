import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct DevicePodcastConfigurationServiceTests {
    @Test
    func savingPodcastDirectoryOnlyWritesTargetFolderAndRootDotfile() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem()
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )

        let updatedDevice = try service.savePodcastDirectoryPath("Podcasts", on: device)

        #expect(updatedDevice.podcastDirectoryURL == URL(fileURLWithPath: "/Volumes/WALKMAN/Podcasts", isDirectory: true))
        #expect(fileSystem.createdDirectories == [
            URL(fileURLWithPath: "/Volumes/WALKMAN/Podcasts", isDirectory: true).standardizedFileURL,
        ])
        #expect(fileSystem.writtenFiles.map(\.url) == [
            URL(fileURLWithPath: "/Volumes/WALKMAN/.spmconfig", isDirectory: false).standardizedFileURL,
        ])
        #expect(fileSystem.writtenFiles.first?.contents == """
        [simple-podcast-manager]
        podcast-dir: Podcasts

        """)
    }

    @Test
    func invalidPodcastDirectoryDoesNotWriteAnything() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem()
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )

        #expect(throws: DevicePodcastConfigurationError.invalidPodcastDirectoryPath("../Podcasts")) {
            _ = try service.savePodcastDirectoryPath("../Podcasts", on: device)
        }
        #expect(fileSystem.createdDirectories.isEmpty)
        #expect(fileSystem.writtenFiles.isEmpty)
    }

    @Test
    func checkingForMissingPodcastDirectoryDoesNotWriteAnything() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem(existingDirectories: [
            URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true).standardizedFileURL,
        ])
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "WALKMAN",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
        )

        let exists = try service.podcastDirectoryExists("Podcasts", on: device)

        #expect(!exists)
        #expect(fileSystem.createdDirectories.isEmpty)
        #expect(fileSystem.writtenFiles.isEmpty)
    }
}

private final class RecordingDevicePodcastConfigurationFileSystem: DevicePodcastConfigurationFileSystem, @unchecked Sendable {
    private let existingDirectories: Set<URL>
    private(set) var createdDirectories: [URL] = []
    private(set) var writtenFiles: [(url: URL, contents: String)] = []

    init(existingDirectories: Set<URL> = []) {
        self.existingDirectories = existingDirectories
    }

    func directoryExists(at url: URL) -> Bool {
        existingDirectories.contains(url.standardizedFileURL)
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url.standardizedFileURL)
    }

    func writeString(_ string: String, to url: URL) throws {
        writtenFiles.append((url.standardizedFileURL, string))
    }
}
