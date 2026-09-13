import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct M3UPlaylistEncoderTests {
    @Test
    func encodesUTF8PathsRelativeToPlaylistFolder() throws {
        let device = makeDevice()
        let episodeURL = device.podcastDirectoryURL
            .appendingPathComponent("Hörspiel", isDirectory: true)
            .appendingPathComponent("Größte Folge.mp3", isDirectory: false)

        let data = try M3UPlaylistEncoder().encode(
            fileURLs: [episodeURL],
            relativeTo: device.playlistDirectoryURL,
            on: device
        )

        #expect(String(decoding: data, as: UTF8.self) == "#EXTM3U\nHörspiel\\Größte Folge.mp3\n")
    }

    @Test
    func encodesPathFromRootPlaylistFolderToPodcastFolder() throws {
        let device = DeviceInfo(
            name: "Test Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-PLAYER/Podcast", isDirectory: true),
            playlistDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-PLAYER/playlist_data", isDirectory: true)
        )
        let episodeURL = device.podcastDirectoryURL
            .appendingPathComponent("Global News Podcast", isDirectory: true)
            .appendingPathComponent("2026.09.11-News.mp3", isDirectory: false)

        let data = try M3UPlaylistEncoder().encode(
            fileURLs: [episodeURL],
            relativeTo: device.playlistDirectoryURL,
            on: device
        )

        #expect(
            String(decoding: data, as: UTF8.self)
                == "#EXTM3U\n..\\Podcast\\Global News Podcast\\2026.09.11-News.mp3\n"
        )
    }

    @Test
    func rejectsEpisodeOutsideDeviceRoot() {
        let device = makeDevice()
        let outsideURL = URL(fileURLWithPath: "/Volumes/OTHER/Episode.mp3")

        #expect(throws: SafetyValidationError.pathOutsideDeviceRoot(outsideURL)) {
            try M3UPlaylistEncoder().encode(
                fileURLs: [outsideURL],
                relativeTo: device.playlistDirectoryURL,
                on: device
            )
        }
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "Test Player",
            rootURL: URL(fileURLWithPath: "/Volumes/TEST-PLAYER", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST-PLAYER/MUSIC", isDirectory: true)
        )
    }
}
