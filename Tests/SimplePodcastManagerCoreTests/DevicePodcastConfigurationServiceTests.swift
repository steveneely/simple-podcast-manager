import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct DevicePodcastConfigurationServiceTests {
    @Test
    func savingPodcastDirectoryOnlyWritesTargetFolderAndRootDotfile() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem()
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/music", isDirectory: true)
        )

        let updatedDevice = try service.savePodcastDirectoryPath("Podcasts", on: device)

        #expect(updatedDevice.podcastDirectoryURL == URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/Podcasts", isDirectory: true))
        #expect(fileSystem.createdDirectories == [
            URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/Podcasts", isDirectory: true).standardizedFileURL,
        ])
        #expect(fileSystem.writtenFiles.map(\.url) == [
            URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/.spmconfig", isDirectory: false).standardizedFileURL,
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
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/music", isDirectory: true)
        )

        #expect(throws: DevicePodcastConfigurationError.invalidPodcastDirectoryPath("../Podcasts")) {
            _ = try service.savePodcastDirectoryPath("../Podcasts", on: device)
        }
        #expect(fileSystem.createdDirectories.isEmpty)
        #expect(fileSystem.writtenFiles.isEmpty)
    }

    @Test
    func savingSeparatePlaylistDirectoryCreatesItAndWritesBothPaths() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem()
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/Podcast", isDirectory: true)
        )

        let updatedDevice = try service.saveDirectoryPaths(
            podcastDirectoryPath: "Podcast",
            playlistDirectoryPath: "playlist_data",
            on: device
        )

        #expect(updatedDevice.podcastDirectoryURL.path == "/Volumes/TEST-MP3-PLAYER/Podcast")
        #expect(updatedDevice.playlistDirectoryURL.path == "/Volumes/TEST-MP3-PLAYER/playlist_data")
        #expect(fileSystem.createdDirectories == [
            URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/Podcast", isDirectory: true).standardizedFileURL,
            URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/playlist_data", isDirectory: true).standardizedFileURL,
        ])
        #expect(fileSystem.writtenFiles.first?.contents == """
        [simple-podcast-manager]
        podcast-dir: Podcast
        playlist-dir: playlist_data

        """)
    }

    @Test
    func checkingForMissingPodcastDirectoryDoesNotWriteAnything() throws {
        let fileSystem = RecordingDevicePodcastConfigurationFileSystem(existingDirectories: [
            URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/music", isDirectory: true).standardizedFileURL,
        ])
        let service = DevicePodcastConfigurationService(fileSystem: fileSystem)
        let device = DeviceInfo(
            name: "Test MP3 Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-MP3-PLAYER/music", isDirectory: true)
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
