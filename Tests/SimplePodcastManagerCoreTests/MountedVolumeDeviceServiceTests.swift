import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct MountedVolumeDeviceServiceTests {
    @Test
    func detectsRemovableVolumeWithPodcastDirectory() throws {
        let service = MountedVolumeDeviceService(
            mountedVolumeProvider: StubMountedVolumeProvider(urls: [
                URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            ]),
            metadataProvider: StubVolumeMetadataProvider(
                resourceValues: [
                    "/Volumes/WALKMAN": MountedVolumeResourceValues(
                        volumeName: "WALKMAN",
                        isDirectory: true,
                        isRemovable: true,
                        isEjectable: true
                    ),
                ],
                childDirectories: [
                    "/Volumes/WALKMAN": [
                        URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
                    ]
                ]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.count == 1)
        #expect(devices.first?.name == "WALKMAN")
        #expect(devices.first?.podcastDirectoryURL == URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true))
    }

    @Test
    func detectsRemovableVolumeWithUppercasePodcastDirectory() throws {
        let service = MountedVolumeDeviceService(
            mountedVolumeProvider: StubMountedVolumeProvider(urls: [
                URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            ]),
            metadataProvider: StubVolumeMetadataProvider(
                resourceValues: [
                    "/Volumes/WALKMAN": MountedVolumeResourceValues(
                        volumeName: "WALKMAN",
                        isDirectory: true,
                        isRemovable: true,
                        isEjectable: true
                    ),
                ],
                childDirectories: [
                    "/Volumes/WALKMAN": [
                        URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC", isDirectory: true)
                    ]
                ]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.count == 1)
        #expect(devices.first?.podcastDirectoryURL == URL(fileURLWithPath: "/Volumes/WALKMAN/MUSIC", isDirectory: true))
    }

    @Test
    func detectsConfiguredPodcastDirectoryFromDotfile() throws {
        let service = MountedVolumeDeviceService(
            mountedVolumeProvider: StubMountedVolumeProvider(urls: [
                URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            ]),
            metadataProvider: StubVolumeMetadataProvider(
                resourceValues: [
                    "/Volumes/WALKMAN": MountedVolumeResourceValues(
                        volumeName: "WALKMAN",
                        isDirectory: true,
                        isRemovable: true,
                        isEjectable: true
                    ),
                ],
                childDirectories: [
                    "/Volumes/WALKMAN": [
                        URL(fileURLWithPath: "/Volumes/WALKMAN/Podcasts", isDirectory: true)
                    ]
                ],
                fileContents: [
                    "/Volumes/WALKMAN/.spmconfig": """
                    [simple-podcast-manager]
                    podcast-dir: Podcasts

                    """
                ]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.count == 1)
        #expect(devices.first?.podcastDirectoryURL == URL(fileURLWithPath: "/Volumes/WALKMAN/Podcasts", isDirectory: true))
    }

    @Test
    func ignoresVolumesWithoutPodcastDirectory() throws {
        let service = MountedVolumeDeviceService(
            mountedVolumeProvider: StubMountedVolumeProvider(urls: [
                URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
            ]),
            metadataProvider: StubVolumeMetadataProvider(
                resourceValues: [
                    "/Volumes/WALKMAN": MountedVolumeResourceValues(
                        volumeName: "WALKMAN",
                        isDirectory: true,
                        isRemovable: true,
                        isEjectable: true
                    ),
                ],
                childDirectories: [:]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.isEmpty)
    }

    @Test
    func ignoresNonRemovableVolumes() throws {
        let service = MountedVolumeDeviceService(
            mountedVolumeProvider: StubMountedVolumeProvider(urls: [
                URL(fileURLWithPath: "/Volumes/InternalDisk", isDirectory: true),
            ]),
            metadataProvider: StubVolumeMetadataProvider(
                resourceValues: [
                    "/Volumes/InternalDisk": MountedVolumeResourceValues(
                        volumeName: "InternalDisk",
                        isDirectory: true,
                        isRemovable: false,
                        isEjectable: false
                    ),
                ],
                childDirectories: [
                    "/Volumes/InternalDisk": [
                        URL(fileURLWithPath: "/Volumes/InternalDisk/music", isDirectory: true)
                    ]
                ]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.isEmpty)
    }
}

private struct StubMountedVolumeProvider: MountedVolumeProviding {
    let urls: [URL]

    func mountedVolumeURLs() -> [URL] {
        urls
    }
}

private struct StubVolumeMetadataProvider: VolumeMetadataProviding {
    let resourceValues: [String: MountedVolumeResourceValues]
    let childDirectories: [String: [URL]]
    var fileContents: [String: String] = [:]

    func resourceValues(for url: URL) throws -> MountedVolumeResourceValues {
        resourceValues[url.standardizedFileURL.path] ?? MountedVolumeResourceValues(
            volumeName: nil,
            isDirectory: false,
            isRemovable: false,
            isEjectable: false
        )
    }

    func directoryExists(at url: URL) -> Bool {
        childDirectories[url.deletingLastPathComponent().standardizedFileURL.path]?
            .contains(url.standardizedFileURL) == true
    }

    func childDirectories(in url: URL) throws -> [URL] {
        childDirectories[url.standardizedFileURL.path] ?? []
    }

    func fileExists(at url: URL) -> Bool {
        fileContents[url.standardizedFileURL.path] != nil
    }

    func stringContents(of url: URL) throws -> String {
        fileContents[url.standardizedFileURL.path] ?? ""
    }
}
