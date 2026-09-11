import Testing
@testable import SimplePodcastManagerCore

struct DevicePodcastConfigurationTests {
    @Test
    func parsesPodcastDirectoryFromAppSection() throws {
        let configuration = try DevicePodcastConfiguration(contents: """
        [other-app]
        podcast-dir: IgnoreMe

        [simple-podcast-manager]
        podcast-dir: Podcasts

        """)

        #expect(configuration.podcastDirectoryPath == "Podcasts")
        #expect(configuration.playlistDirectoryPath == nil)
        #expect(configuration.resolvedPlaylistDirectoryPath == "Podcasts")
    }

    @Test
    func parsesSeparatePlaylistDirectoryFromAppSection() throws {
        let configuration = try DevicePodcastConfiguration(contents: """
        [simple-podcast-manager]
        podcast-dir: Podcast
        playlist-dir: playlist_data

        """)

        #expect(configuration.podcastDirectoryPath == "Podcast")
        #expect(configuration.playlistDirectoryPath == "playlist_data")
        #expect(configuration.resolvedPlaylistDirectoryPath == "playlist_data")
    }

    @Test
    func defaultsToMusicWhenPodcastDirectoryIsMissing() throws {
        let configuration = try DevicePodcastConfiguration(contents: """
        [simple-podcast-manager]

        """)

        #expect(configuration.podcastDirectoryPath == "music")
    }

    @Test
    func rejectsAbsoluteOrEscapingPodcastDirectories() throws {
        #expect(throws: DevicePodcastConfigurationError.invalidPodcastDirectoryPath("/tmp")) {
            _ = try DevicePodcastConfiguration(podcastDirectoryPath: "/tmp")
        }

        #expect(throws: DevicePodcastConfigurationError.invalidPodcastDirectoryPath("../Podcasts")) {
            _ = try DevicePodcastConfiguration(podcastDirectoryPath: "../Podcasts")
        }

        #expect(throws: DevicePodcastConfigurationError.invalidPlaylistDirectoryPath("/playlist_data")) {
            _ = try DevicePodcastConfiguration(playlistDirectoryPath: "/playlist_data")
        }

        #expect(throws: DevicePodcastConfigurationError.invalidPlaylistDirectoryPath("../playlist_data")) {
            _ = try DevicePodcastConfiguration(playlistDirectoryPath: "../playlist_data")
        }
    }
}
