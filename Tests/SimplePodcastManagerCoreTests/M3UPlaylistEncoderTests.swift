import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct M3UPlaylistEncoderTests {
    @Test
    func encodesWalkmanCompatibleRootRelativeUTF8Paths() throws {
        let device = makeDevice()
        let episodeURL = device.podcastDirectoryURL
            .appendingPathComponent("Hörspiel", isDirectory: true)
            .appendingPathComponent("Größte Folge.mp3", isDirectory: false)

        let data = try M3UPlaylistEncoder().encode(fileURLs: [episodeURL], on: device)

        #expect(String(decoding: data, as: UTF8.self) == "#EXTM3U\n\\MUSIC\\Hörspiel\\Größte Folge.mp3\n")
    }

    @Test
    func rejectsEpisodeOutsideDeviceRoot() {
        let device = makeDevice()
        let outsideURL = URL(fileURLWithPath: "/Volumes/OTHER/Episode.mp3")

        #expect(throws: SafetyValidationError.pathOutsideDeviceRoot(outsideURL)) {
            try M3UPlaylistEncoder().encode(fileURLs: [outsideURL], on: device)
        }
    }

    private func makeDevice() -> DeviceInfo {
        DeviceInfo(
            name: "Walkman",
            rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC", isDirectory: true)
        )
    }
}
