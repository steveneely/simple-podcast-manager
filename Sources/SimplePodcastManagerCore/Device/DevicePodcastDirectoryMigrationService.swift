import Foundation

public struct DevicePodcastDirectoryMigrationItem: Equatable, Sendable {
    public var sourceURL: URL
    public var destinationURL: URL

    public init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL.standardizedFileURL
    }
}

public struct DevicePodcastDirectoryPlaylistUpdate: Equatable, Sendable {
    public let url: URL
    public let originalData: Data
    public let updatedData: Data
}

public struct DevicePodcastDirectoryMigrationPlan: Equatable, Sendable {
    public var currentDevice: DeviceInfo
    public var updatedDevice: DeviceInfo
    public var podcastDirectoryPath: String
    public var items: [DevicePodcastDirectoryMigrationItem]
    public var playlistUpdates: [DevicePodcastDirectoryPlaylistUpdate]

    public init(
        currentDevice: DeviceInfo,
        updatedDevice: DeviceInfo,
        podcastDirectoryPath: String,
        items: [DevicePodcastDirectoryMigrationItem],
        playlistUpdates: [DevicePodcastDirectoryPlaylistUpdate] = []
    ) {
        self.currentDevice = currentDevice
        self.updatedDevice = updatedDevice
        self.podcastDirectoryPath = podcastDirectoryPath
        self.items = items
        self.playlistUpdates = playlistUpdates
    }
}

public struct DevicePodcastDirectoryMigrationService: Sendable {
    private let fileSystem: any DevicePodcastDirectoryMigrationFileSystem
    private let configurationService: DevicePodcastConfigurationService
    private let safetyValidator: SafetyValidator

    public init(
        fileSystem: any DevicePodcastDirectoryMigrationFileSystem = LocalDevicePodcastDirectoryMigrationFileSystem(),
        configurationService: DevicePodcastConfigurationService = DevicePodcastConfigurationService(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.fileSystem = fileSystem
        self.configurationService = configurationService
        self.safetyValidator = safetyValidator
    }

    public func makePlan(
        podcastDirectoryPath: String,
        on device: DeviceInfo,
        managedFileURLs: [URL],
        subscriptions: [PodcastSubscription],
        playlistState: PodcastPlaylistDeviceState? = nil
    ) throws -> DevicePodcastDirectoryMigrationPlan {
        let configuration = try DevicePodcastConfiguration(podcastDirectoryPath: podcastDirectoryPath)
        let updatedDevice = DeviceInfo(
            name: device.name,
            rootURL: device.rootURL,
            podcastDirectoryURL: device.rootURL.appending(
                path: configuration.podcastDirectoryPath,
                directoryHint: .isDirectory
            ).standardizedFileURL,
            playlistDirectoryURL: device.playlistDirectoryURL
        )

        try validateMigrationDevices(currentDevice: device, updatedDevice: updatedDevice)

        guard device.podcastDirectoryURL.standardizedFileURL != updatedDevice.podcastDirectoryURL.standardizedFileURL else {
            return DevicePodcastDirectoryMigrationPlan(
                currentDevice: device,
                updatedDevice: updatedDevice,
                podcastDirectoryPath: configuration.podcastDirectoryPath,
                items: []
            )
        }

        let items = try Set(managedFileURLs.map(\.standardizedFileURL))
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            .map { sourceURL in
                try makeMigrationItem(
                    sourceURL: sourceURL,
                    currentDevice: device,
                    updatedDevice: updatedDevice,
                    subscriptions: subscriptions
                )
            }

        return DevicePodcastDirectoryMigrationPlan(
            currentDevice: device,
            updatedDevice: updatedDevice,
            podcastDirectoryPath: configuration.podcastDirectoryPath,
            items: items,
            playlistUpdates: try makePlaylistUpdates(items: items, on: device, playlistState: playlistState)
        )
    }

    @discardableResult
    public func execute(
        _ plan: DevicePodcastDirectoryMigrationPlan,
        subscriptions: [PodcastSubscription],
        playlistState: PodcastPlaylistDeviceState? = nil,
        playlistDirectoryPath: String? = nil
    ) throws -> DeviceInfo {
        try validateMigrationDevices(
            currentDevice: plan.currentDevice,
            updatedDevice: plan.updatedDevice
        )

        let expectedConfiguration = try DevicePodcastConfiguration(
            podcastDirectoryPath: plan.podcastDirectoryPath
        )
        let expectedPodcastDirectoryURL = plan.currentDevice.rootURL.appending(
            path: expectedConfiguration.podcastDirectoryPath,
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard expectedPodcastDirectoryURL == plan.updatedDevice.podcastDirectoryURL.standardizedFileURL else {
            throw DevicePodcastDirectoryMigrationError.invalidPlan
        }

        for item in plan.items {
            let expectedItem = try makeMigrationItem(
                sourceURL: item.sourceURL,
                currentDevice: plan.currentDevice,
                updatedDevice: plan.updatedDevice,
                subscriptions: subscriptions
            )
            guard expectedItem == item else {
                throw DevicePodcastDirectoryMigrationError.invalidPlan
            }
            guard fileSystem.fileExists(at: item.sourceURL) else {
                throw DevicePodcastDirectoryMigrationError.sourceFileMissing(item.sourceURL)
            }
            guard !fileSystem.fileExists(at: item.destinationURL) else {
                throw DevicePodcastDirectoryMigrationError.destinationAlreadyExists(item.destinationURL)
            }
        }

        // Rebuild from current ownership and bytes; never trust a stale reviewed write.
        let expectedUpdates = try makePlaylistUpdates(
            items: plan.items, on: plan.currentDevice, playlistState: playlistState
        )
        guard expectedUpdates == plan.playlistUpdates else {
            throw DevicePodcastDirectoryMigrationError.invalidPlan
        }
        var completedPlaylistUpdates: [DevicePodcastDirectoryPlaylistUpdate] = []
        var completedItems: [DevicePodcastDirectoryMigrationItem] = []
        do {
            for item in plan.items {
                try fileSystem.createDirectory(at: item.destinationURL.deletingLastPathComponent())
                try fileSystem.moveItem(at: item.sourceURL, to: item.destinationURL)
                completedItems.append(item)
            }

            for update in plan.playlistUpdates {
                try validatePlaylistTarget(update.url, on: plan.currentDevice)
                guard try fileSystem.readData(at: update.url) == update.originalData else {
                    throw DevicePodcastDirectoryMigrationError.invalidPlan
                }
                try fileSystem.writeData(update.updatedData, to: update.url)
                completedPlaylistUpdates.append(update)
            }
            let updatedDevice: DeviceInfo
            if let playlistDirectoryPath {
                updatedDevice = try configurationService.saveDirectoryPaths(
                    podcastDirectoryPath: plan.podcastDirectoryPath,
                    playlistDirectoryPath: playlistDirectoryPath,
                    on: plan.currentDevice
                )
            } else {
                updatedDevice = try configurationService.savePodcastDirectoryPath(
                    plan.podcastDirectoryPath, on: plan.currentDevice
                )
            }
            cleanupEmptySourceDirectories(
                afterMoving: plan.items,
                on: plan.currentDevice
            )
            return updatedDevice
        } catch {
            var rollbackFailed = false
            for update in completedPlaylistUpdates.reversed() {
                do {
                    try validatePlaylistTarget(update.url, on: plan.currentDevice)
                    try fileSystem.writeData(update.originalData, to: update.url)
                } catch { rollbackFailed = true }
            }
            do { try rollback(completedItems) } catch { rollbackFailed = true }
            if rollbackFailed {
                throw DevicePodcastDirectoryMigrationError.rollbackFailed
            }
            throw error
        }
    }

    private func validatePlaylistTarget(_ url: URL, on device: DeviceInfo) throws {
        try safetyValidator.validatePodcastPlaylistTarget(url, on: device)
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else {
            throw DevicePodcastDirectoryMigrationError.invalidPlaylist(url)
        }
    }

    private func makePlaylistUpdates(
        items: [DevicePodcastDirectoryMigrationItem],
        on device: DeviceInfo,
        playlistState: PodcastPlaylistDeviceState?
    ) throws -> [DevicePodcastDirectoryPlaylistUpdate] {
        guard !items.isEmpty, let playlistState,
              let ownedDirectoryPath = playlistState.playlistDirectoryPath,
              device.rootURL.appendingPathComponent(ownedDirectoryPath, isDirectory: true).standardizedFileURL
                == device.playlistDirectoryURL.standardizedFileURL else { return [] }
        let encoder = M3UPlaylistEncoder()
        var replacements: [String: String] = [:]
        for item in items {
            func entry(_ url: URL) throws -> String {
                let data = try encoder.encode(fileURLs: [url], relativeTo: device.playlistDirectoryURL, on: device)
                return String(decoding: data, as: UTF8.self).components(separatedBy: "\n")[1]
            }
            replacements[try entry(item.sourceURL)] = try entry(item.destinationURL)
        }
        return try playlistState.ownedDeviceFileNames.sorted().compactMap { name in
            guard name == URL(fileURLWithPath: name).lastPathComponent else {
                throw DevicePodcastDirectoryMigrationError.invalidPlan
            }
            let url = device.playlistDirectoryURL.appendingPathComponent(name)
            try validatePlaylistTarget(url, on: device)
            guard fileSystem.fileExists(at: url) else { return nil }
            let original = try fileSystem.readData(at: url)
            guard let text = String(data: original, encoding: .utf8), text.hasPrefix("#EXTM3U\n") else {
                throw DevicePodcastDirectoryMigrationError.invalidPlaylist(url)
            }
            let updated = text.components(separatedBy: "\n").map { replacements[$0] ?? $0 }.joined(separator: "\n")
            let data = Data(updated.utf8)
            guard data != original else { return nil }
            return DevicePodcastDirectoryPlaylistUpdate(url: url, originalData: original, updatedData: data)
        }
    }

    private func makeMigrationItem(
        sourceURL: URL,
        currentDevice: DeviceInfo,
        updatedDevice: DeviceInfo,
        subscriptions: [PodcastSubscription]
    ) throws -> DevicePodcastDirectoryMigrationItem {
        let sourceURL = sourceURL.standardizedFileURL
        try safetyValidator.validateDeleteTarget(sourceURL, on: currentDevice)

        let sourceParentURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        guard sourceParentURL.deletingLastPathComponent().standardizedFileURL
                == currentDevice.podcastDirectoryURL.standardizedFileURL,
              subscriptions.contains(where: { EpisodeFileName.isManagedEpisodeFile(sourceURL, for: $0) }) else {
            throw DevicePodcastDirectoryMigrationError.fileIsNotAppManaged(sourceURL)
        }

        let destinationURL = updatedDevice.podcastDirectoryURL
            .appendingPathComponent(sourceParentURL.lastPathComponent, isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        try safetyValidator.validateWriteTarget(destinationURL, on: updatedDevice)

        return DevicePodcastDirectoryMigrationItem(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
    }

    private func validateMigrationDevices(
        currentDevice: DeviceInfo,
        updatedDevice: DeviceInfo
    ) throws {
        try safetyValidator.validateDevice(currentDevice)
        try safetyValidator.validateDevice(updatedDevice)
        guard currentDevice.rootURL.resolvingSymlinksInPath().standardizedFileURL
                == updatedDevice.rootURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw DevicePodcastDirectoryMigrationError.invalidPlan
        }
    }

    private func rollback(_ completedItems: [DevicePodcastDirectoryMigrationItem]) throws {
        for item in completedItems.reversed() {
            guard fileSystem.fileExists(at: item.destinationURL) else { continue }
            try fileSystem.createDirectory(at: item.sourceURL.deletingLastPathComponent())
            try fileSystem.moveItem(at: item.destinationURL, to: item.sourceURL)
        }
    }

    private func cleanupEmptySourceDirectories(
        afterMoving items: [DevicePodcastDirectoryMigrationItem],
        on device: DeviceInfo
    ) {
        let sourceDirectories = Set(
            items.map { $0.sourceURL.deletingLastPathComponent().standardizedFileURL }
        )

        for directoryURL in sourceDirectories {
            removeMetadataSidecars(for: items, in: directoryURL, on: device)

            guard fileSystem.fileExists(at: directoryURL),
                  let contents = try? fileSystem.contentsOfDirectory(at: directoryURL),
                  contents.isEmpty else {
                continue
            }

            do {
                try safetyValidator.validateDeleteTarget(directoryURL, on: device)
                try fileSystem.removeItem(at: directoryURL)

                let directorySidecarURL = directoryURL.deletingLastPathComponent()
                    .appendingPathComponent("._" + directoryURL.lastPathComponent, isDirectory: false)
                    .standardizedFileURL
                if fileSystem.fileExists(at: directorySidecarURL) {
                    try safetyValidator.validateDeleteTarget(directorySidecarURL, on: device)
                    try fileSystem.removeItem(at: directorySidecarURL)
                }
            } catch {
                // File migration and configuration succeeded. Leaving harmless empty
                // metadata behind is safer than reporting the whole migration failed.
                continue
            }
        }
    }

    private func removeMetadataSidecars(
        for items: [DevicePodcastDirectoryMigrationItem],
        in directoryURL: URL,
        on device: DeviceInfo
    ) {
        let sidecarURLs = items
            .filter { $0.sourceURL.deletingLastPathComponent().standardizedFileURL == directoryURL }
            .map {
                directoryURL.appendingPathComponent(
                    "._" + $0.sourceURL.lastPathComponent,
                    isDirectory: false
                ).standardizedFileURL
            }

        for sidecarURL in sidecarURLs where fileSystem.fileExists(at: sidecarURL) {
            do {
                try safetyValidator.validateDeleteTarget(sidecarURL, on: device)
                try fileSystem.removeItem(at: sidecarURL)
            } catch {
                continue
            }
        }
    }
}

public enum DevicePodcastDirectoryMigrationError: Error, Equatable, LocalizedError, Sendable {
    case invalidPlan
    case invalidPlaylist(URL)
    case fileIsNotAppManaged(URL)
    case sourceFileMissing(URL)
    case destinationAlreadyExists(URL)
    case rollbackFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPlaylist(let url):
            return "The playlist \"\(url.lastPathComponent)\" could not be updated safely. No files were moved."
        case .invalidPlan:
            return "The podcast folder migration plan is no longer valid. No files were moved."
        case .fileIsNotAppManaged(let url):
            return "The file \"\(url.lastPathComponent)\" is not clearly managed by Simple Podcast Manager, so it was not moved."
        case .sourceFileMissing(let url):
            return "The file \"\(url.lastPathComponent)\" is no longer on the device. Refresh the device and try again."
        case .destinationAlreadyExists(let url):
            return "A file named \"\(url.lastPathComponent)\" already exists in the new podcast folder. No files were moved."
        case .rollbackFailed:
            return "The podcast folder migration failed and some completed moves could not be reversed. Check both podcast folders before syncing."
        }
    }
}

public protocol DevicePodcastDirectoryMigrationFileSystem: Sendable {
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func removeItem(at url: URL) throws
}

public struct LocalDevicePodcastDirectoryMigrationFileSystem: DevicePodcastDirectoryMigrationFileSystem {
    public init() {}

    public func readData(at url: URL) throws -> Data { try Data(contentsOf: url) }

    public func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
