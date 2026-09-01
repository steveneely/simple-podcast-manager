import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct VolumeMetadataProvidingTests {
    @Test
    func detectsConfigurationAndDirectoryWhenVolumePathRequiresPercentEncoding() throws {
        let fileManager = FileManager.default
        let volumeURL = fileManager.temporaryDirectory.appendingPathComponent(
            "HIBY R1 #\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: volumeURL) }

        let podcastDirectoryURL = volumeURL.appendingPathComponent("Podcast", isDirectory: true)
        let configurationURL = volumeURL.appendingPathComponent(".spmconfig", isDirectory: false)
        try fileManager.createDirectory(at: podcastDirectoryURL, withIntermediateDirectories: true)
        try """
        [simple-podcast-manager]
        podcast-dir: Podcast

        """.write(to: configurationURL, atomically: true, encoding: .utf8)

        let provider = FileSystemVolumeMetadataProvider()

        #expect(provider.directoryExists(at: podcastDirectoryURL))
        #expect(provider.fileExists(at: configurationURL))
        #expect(try provider.stringContents(of: configurationURL).contains("podcast-dir: Podcast"))
    }
}
