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
    }
}
