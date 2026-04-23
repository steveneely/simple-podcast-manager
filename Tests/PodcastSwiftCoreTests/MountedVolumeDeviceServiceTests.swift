import Foundation
import Testing
@testable import PodcastSwiftCore

struct MountedVolumeDeviceServiceTests {
    @Test
    func detectsRemovableVolumeWithMusicDirectory() throws {
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
                directories: [
                    "/Volumes/WALKMAN/music",
                ]
            ),
            safetyValidator: SafetyValidator(homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        )

        let devices = try service.discoverDevices()

        #expect(devices.count == 1)
        #expect(devices.first?.name == "WALKMAN")
        #expect(devices.first?.musicURL == URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true))
    }

    @Test
    func ignoresVolumesWithoutMusicDirectory() throws {
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
                directories: []
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
                directories: [
                    "/Volumes/InternalDisk/music",
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
    let directories: Set<String>

    func resourceValues(for url: URL) throws -> MountedVolumeResourceValues {
        resourceValues[url.standardizedFileURL.path] ?? MountedVolumeResourceValues(
            volumeName: nil,
            isDirectory: false,
            isRemovable: false,
            isEjectable: false
        )
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.standardizedFileURL.path)
    }
}
