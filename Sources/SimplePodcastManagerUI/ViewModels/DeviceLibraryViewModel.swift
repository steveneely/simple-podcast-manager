import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class DeviceLibraryViewModel {
    public private(set) var filesBySubscriptionID: [UUID: [URL]]
    public private(set) var otherAudioFiles: [URL]
    public private(set) var lastErrorMessage: String?

    private let deviceLibrary: any DeviceLibraryInspecting
    private let managedDirectoryResolver: ManagedDirectoryResolver
    private let fileSystem: any FileSystemOperating
    private let safetyValidator: SafetyValidator
    private var latestRefreshID: UUID?

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.deviceLibrary = deviceLibrary
        self.managedDirectoryResolver = ManagedDirectoryResolver(deviceLibrary: deviceLibrary)
        self.fileSystem = fileSystem
        self.safetyValidator = safetyValidator
        self.filesBySubscriptionID = [:]
        self.otherAudioFiles = []
        self.lastErrorMessage = nil
    }

    public func refresh(device: DeviceInfo?, subscriptions: [FeedSubscription]) async {
        let refreshID = UUID()
        latestRefreshID = refreshID

        guard let device else {
            filesBySubscriptionID = [:]
            otherAudioFiles = []
            lastErrorMessage = nil
            return
        }

        do {
            try safetyValidator.validateDevice(device)
            let deviceLibrary = deviceLibrary
            let managedDirectoryResolver = managedDirectoryResolver
            let inventory = try await Task.detached(priority: .userInitiated) {
                try Self.makeInventory(
                    deviceLibrary: deviceLibrary,
                    managedDirectoryResolver: managedDirectoryResolver,
                    device: device,
                    subscriptions: subscriptions
                )
            }.value
            guard latestRefreshID == refreshID else { return }

            filesBySubscriptionID = inventory.filesBySubscriptionID
            otherAudioFiles = inventory.otherAudioFiles
            lastErrorMessage = nil
        } catch {
            guard latestRefreshID == refreshID else { return }
            filesBySubscriptionID = [:]
            otherAudioFiles = []
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func files(for subscription: FeedSubscription) -> [URL] {
        filesBySubscriptionID[subscription.id] ?? []
    }

    public func deleteOtherAudioFiles(_ fileURLs: Set<URL>, on device: DeviceInfo?) {
        guard let device else { return }

        do {
            let knownOtherAudioFiles = Set(otherAudioFiles.map(\.standardizedFileURL))
            var deletedURLs: Set<URL> = []

            for standardizedURL in fileURLs.map(\.standardizedFileURL) {
                guard knownOtherAudioFiles.contains(standardizedURL) else {
                    continue
                }

                try safetyValidator.validateDeleteTarget(standardizedURL, on: device)
                try fileSystem.removeItem(at: standardizedURL)
                try removeAppleDoubleSidecarIfPresent(for: standardizedURL, on: device)
                deletedURLs.insert(standardizedURL)
            }

            otherAudioFiles.removeAll { deletedURLs.contains($0.standardizedFileURL) }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    nonisolated private static func makeInventory(
        deviceLibrary: any DeviceLibraryInspecting,
        managedDirectoryResolver: ManagedDirectoryResolver,
        device: DeviceInfo,
        subscriptions: [FeedSubscription]
    ) throws -> DeviceLibraryInventory {
        let deviceSnapshot = try DeviceLibrarySnapshot(
            deviceLibrary: deviceLibrary,
            directoryURL: device.podcastDirectoryURL
        )
        var filesBySubscriptionID: [UUID: [URL]] = [:]
        for subscription in subscriptions {
            let managedDirectoryURL = managedDirectoryResolver.managedDirectoryURL(
                for: subscription,
                on: device,
                candidateDirectories: deviceSnapshot.directories
            )
            let files = deviceSnapshot.directFiles(in: managedDirectoryURL)
                .filter { EpisodeFileName.isManagedEpisodeFile($0, for: subscription) }
            filesBySubscriptionID[subscription.id] = sortFiles(files)
        }

        return DeviceLibraryInventory(
            filesBySubscriptionID: filesBySubscriptionID,
            otherAudioFiles: otherAudioFiles(in: deviceSnapshot.files, subscriptions: subscriptions)
        )
    }

    nonisolated private static func sortFiles(_ files: [URL]) -> [URL] {
        files.sorted { lhs, rhs in
            switch (EpisodeFileName.publicationDate(from: lhs), EpisodeFileName.publicationDate(from: rhs)) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    nonisolated private static func otherAudioFiles(
        in deviceFiles: [URL],
        subscriptions: [FeedSubscription]
    ) -> [URL] {
        deviceFiles
            .filter { isAudioFile($0) }
            .filter { !isAppleDoubleSidecar($0) }
            .filter { fileURL in
                !subscriptions.contains(where: { EpisodeFileName.isManagedEpisodeFile(fileURL, for: $0) })
            }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
    }

    nonisolated private static func isAudioFile(_ fileURL: URL) -> Bool {
        let audioExtensions = Set(["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma"])
        return audioExtensions.contains(fileURL.pathExtension.lowercased())
    }

    nonisolated private static func isAppleDoubleSidecar(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasPrefix("._")
    }

    private func removeAppleDoubleSidecarIfPresent(for fileURL: URL, on device: DeviceInfo) throws {
        let sidecarURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("._" + fileURL.lastPathComponent, isDirectory: false)
        guard fileSystem.fileExists(at: sidecarURL) else { return }

        try safetyValidator.validateDeleteTarget(sidecarURL, on: device)
        try fileSystem.removeItem(at: sidecarURL)
    }
}

private struct DeviceLibraryInventory: Sendable {
    let filesBySubscriptionID: [UUID: [URL]]
    let otherAudioFiles: [URL]
}
