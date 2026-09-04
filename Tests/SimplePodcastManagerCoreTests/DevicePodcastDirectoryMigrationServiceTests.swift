import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct DevicePodcastDirectoryMigrationServiceTests {
    @Test
    func plansOnlyExactManagedFileMovesIntoMatchingPodcastFolders() throws {
        let fixture = MigrationFixture()
        let service = fixture.makeService()

        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        #expect(plan.currentDevice == fixture.device)
        #expect(plan.updatedDevice.podcastDirectoryURL == fixture.newPodcastDirectory)
        #expect(plan.items == [
            DevicePodcastDirectoryMigrationItem(
                sourceURL: fixture.managedFile,
                destinationURL: fixture.newManagedFile
            ),
        ])
    }

    @Test
    func rejectsAFileThatIsNotClearlyAppManaged() throws {
        let fixture = MigrationFixture()
        let unrelatedFile = fixture.device.podcastDirectoryURL
            .appendingPathComponent("ATP/Favorite Song.mp3", isDirectory: false)
        let service = fixture.makeService()

        #expect(throws: DevicePodcastDirectoryMigrationError.fileIsNotAppManaged(unrelatedFile.standardizedFileURL)) {
            _ = try service.makePlan(
                podcastDirectoryPath: "Podcast",
                on: fixture.device,
                managedFileURLs: [unrelatedFile],
                subscriptions: [fixture.subscription]
            )
        }
    }

    @Test
    func executingPlanMovesFilesAndWritesRootConfiguration() throws {
        let fixture = MigrationFixture()
        let fileSystem = RecordingMigrationFileSystem(existingURLs: [fixture.managedFile])
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        let updatedDevice = try service.execute(plan, subscriptions: [fixture.subscription])

        #expect(updatedDevice.podcastDirectoryURL == fixture.newPodcastDirectory)
        #expect(fileSystem.moves == [
            .init(source: fixture.managedFile, destination: fixture.newManagedFile),
        ])
        #expect(fileSystem.existingURLs.contains(fixture.newManagedFile.standardizedFileURL))
        #expect(!fileSystem.existingURLs.contains(fixture.managedFile.standardizedFileURL))
        #expect(fileSystem.writtenFiles == [
            .init(
                url: fixture.device.rootURL.appendingPathComponent(".spmconfig").standardizedFileURL,
                contents: """
                [simple-podcast-manager]
                podcast-dir: Podcast

                """
            ),
        ])
    }

    @Test
    func existingDestinationAbortsBeforeMovingAnything() throws {
        let fixture = MigrationFixture()
        let fileSystem = RecordingMigrationFileSystem(
            existingURLs: [fixture.managedFile, fixture.newManagedFile]
        )
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        #expect(throws: DevicePodcastDirectoryMigrationError.destinationAlreadyExists(fixture.newManagedFile.standardizedFileURL)) {
            _ = try service.execute(plan, subscriptions: [fixture.subscription])
        }
        #expect(fileSystem.moves.isEmpty)
        #expect(fileSystem.writtenFiles.isEmpty)
    }

    @Test
    func configurationWriteFailureRollsCompletedMovesBack() throws {
        let fixture = MigrationFixture()
        let fileSystem = RecordingMigrationFileSystem(
            existingURLs: [fixture.managedFile],
            failsConfigurationWrite: true
        )
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        #expect(throws: MigrationTestError.configurationWriteFailed) {
            _ = try service.execute(plan, subscriptions: [fixture.subscription])
        }
        #expect(fileSystem.moves == [
            .init(source: fixture.managedFile, destination: fixture.newManagedFile),
            .init(source: fixture.newManagedFile, destination: fixture.managedFile),
        ])
        #expect(fileSystem.existingURLs.contains(fixture.managedFile.standardizedFileURL))
        #expect(!fileSystem.existingURLs.contains(fixture.newManagedFile.standardizedFileURL))
    }

    @Test
    func laterMoveFailureRollsEarlierMovesBackWithoutWritingConfiguration() throws {
        let fixture = MigrationFixture()
        let secondManagedFile = fixture.device.podcastDirectoryURL.appendingPathComponent(
            "ATP/2026.09.01-Another Episode-(ATP).mp3",
            isDirectory: false
        )
        let secondDestination = fixture.newPodcastDirectory.appendingPathComponent(
            "ATP/2026.09.01-Another Episode-(ATP).mp3",
            isDirectory: false
        )
        let fileSystem = RecordingMigrationFileSystem(
            existingURLs: [fixture.managedFile, secondManagedFile],
            failingMoveDestination: secondDestination
        )
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile, secondManagedFile],
            subscriptions: [fixture.subscription]
        )

        #expect(throws: MigrationTestError.moveFailed) {
            _ = try service.execute(plan, subscriptions: [fixture.subscription])
        }
        #expect(fileSystem.existingURLs.contains(fixture.managedFile.standardizedFileURL))
        #expect(fileSystem.existingURLs.contains(secondManagedFile.standardizedFileURL))
        #expect(!fileSystem.existingURLs.contains(fixture.newManagedFile.standardizedFileURL))
        #expect(fileSystem.writtenFiles.isEmpty)
    }

    @Test
    func successfulMigrationRemovesEmptySourceDirectoryAndMatchingSidecars() throws {
        let fixture = MigrationFixture()
        let sourceDirectory = fixture.managedFile.deletingLastPathComponent()
        let fileSidecar = sourceDirectory.appendingPathComponent(
            "._" + fixture.managedFile.lastPathComponent,
            isDirectory: false
        )
        let directorySidecar = fixture.device.podcastDirectoryURL.appendingPathComponent(
            "._" + sourceDirectory.lastPathComponent,
            isDirectory: false
        )
        let fileSystem = RecordingMigrationFileSystem(existingURLs: [
            fixture.managedFile,
            sourceDirectory,
            fileSidecar,
            directorySidecar,
        ])
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        _ = try service.execute(plan, subscriptions: [fixture.subscription])

        #expect(fileSystem.removedItems == [
            fileSidecar.standardizedFileURL,
            sourceDirectory.standardizedFileURL,
            directorySidecar.standardizedFileURL,
        ])
        #expect(!fileSystem.existingURLs.contains(sourceDirectory.standardizedFileURL))
    }

    @Test
    func successfulMigrationKeepsSourceDirectoryWhenAnotherFileRemains() throws {
        let fixture = MigrationFixture()
        let sourceDirectory = fixture.managedFile.deletingLastPathComponent()
        let unrelatedFile = sourceDirectory.appendingPathComponent("notes.txt", isDirectory: false)
        let directorySidecar = fixture.device.podcastDirectoryURL.appendingPathComponent(
            "._" + sourceDirectory.lastPathComponent,
            isDirectory: false
        )
        let fileSystem = RecordingMigrationFileSystem(existingURLs: [
            fixture.managedFile,
            sourceDirectory,
            unrelatedFile,
            directorySidecar,
        ])
        let service = fixture.makeService(fileSystem: fileSystem)
        let plan = try service.makePlan(
            podcastDirectoryPath: "Podcast",
            on: fixture.device,
            managedFileURLs: [fixture.managedFile],
            subscriptions: [fixture.subscription]
        )

        _ = try service.execute(plan, subscriptions: [fixture.subscription])

        #expect(fileSystem.existingURLs.contains(sourceDirectory.standardizedFileURL))
        #expect(fileSystem.existingURLs.contains(unrelatedFile.standardizedFileURL))
        #expect(fileSystem.existingURLs.contains(directorySidecar.standardizedFileURL))
        #expect(fileSystem.removedItems.isEmpty)
    }
}

private struct MigrationFixture {
    let subscription = PodcastSubscription(
        title: "ATP",
        rssURL: URL(string: "https://example.com/feed.xml")!
    )
    let device = DeviceInfo(
        name: "WALKMAN",
        rootURL: URL(fileURLWithPath: "/Volumes/WALKMAN", isDirectory: true),
        podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/WALKMAN/music", isDirectory: true)
    )

    var managedFile: URL {
        device.podcastDirectoryURL.appendingPathComponent(
            "ATP/2026.08.31-Episode-(ATP).mp3",
            isDirectory: false
        )
    }

    var newPodcastDirectory: URL {
        device.rootURL.appendingPathComponent("Podcast", isDirectory: true).standardizedFileURL
    }

    var newManagedFile: URL {
        newPodcastDirectory.appendingPathComponent(
            "ATP/2026.08.31-Episode-(ATP).mp3",
            isDirectory: false
        )
    }

    func makeService(
        fileSystem: RecordingMigrationFileSystem = RecordingMigrationFileSystem()
    ) -> DevicePodcastDirectoryMigrationService {
        DevicePodcastDirectoryMigrationService(
            fileSystem: fileSystem,
            configurationService: DevicePodcastConfigurationService(fileSystem: fileSystem),
            safetyValidator: SafetyValidator(
                homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
            )
        )
    }
}

private final class RecordingMigrationFileSystem:
    DevicePodcastDirectoryMigrationFileSystem,
    DevicePodcastConfigurationFileSystem,
    @unchecked Sendable
{
    struct Move: Equatable {
        let source: URL
        let destination: URL
    }

    struct WrittenFile: Equatable {
        let url: URL
        let contents: String
    }

    private(set) var existingURLs: Set<URL>
    private(set) var moves: [Move] = []
    private(set) var writtenFiles: [WrittenFile] = []
    private(set) var removedItems: [URL] = []
    private let failsConfigurationWrite: Bool
    private let failingMoveDestination: URL?

    init(
        existingURLs: [URL] = [],
        failsConfigurationWrite: Bool = false,
        failingMoveDestination: URL? = nil
    ) {
        self.existingURLs = Set(existingURLs.map(\.standardizedFileURL))
        self.failsConfigurationWrite = failsConfigurationWrite
        self.failingMoveDestination = failingMoveDestination?.standardizedFileURL
    }

    func fileExists(at url: URL) -> Bool {
        existingURLs.contains(url.standardizedFileURL)
    }

    func directoryExists(at url: URL) -> Bool {
        existingURLs.contains(url.standardizedFileURL)
    }

    func createDirectory(at url: URL) throws {
        existingURLs.insert(url.standardizedFileURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        moves.append(.init(source: sourceURL, destination: destinationURL))
        if destinationURL == failingMoveDestination {
            throw MigrationTestError.moveFailed
        }
        existingURLs.remove(sourceURL)
        existingURLs.insert(destinationURL)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let directoryURL = url.standardizedFileURL
        return existingURLs.filter {
            $0.deletingLastPathComponent().standardizedFileURL == directoryURL
        }
        .sorted { $0.path < $1.path }
    }

    func removeItem(at url: URL) throws {
        let url = url.standardizedFileURL
        removedItems.append(url)
        existingURLs.remove(url)
    }

    func writeString(_ string: String, to url: URL) throws {
        if failsConfigurationWrite {
            throw MigrationTestError.configurationWriteFailed
        }
        writtenFiles.append(.init(url: url.standardizedFileURL, contents: string))
        existingURLs.insert(url.standardizedFileURL)
    }
}

private enum MigrationTestError: Error {
    case configurationWriteFailed
    case moveFailed
}
