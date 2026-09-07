import Foundation
import Observation
import SimplePodcastManagerCore

@MainActor
@Observable
public final class DeviceLibraryViewModel {
    public private(set) var otherAudioFiles: [URL]
    public private(set) var hasOtherAudioAvailable: Bool
    public private(set) var isReviewingOtherAudio: Bool
    public private(set) var otherAudioReviewInspectedFileCount: Int
    public private(set) var otherAudioReviewMessage: String?
    public private(set) var isRefreshingManagedInventory: Bool
    public private(set) var lastErrorMessage: String?
    public private(set) var managedInventory: ManagedDeviceLibraryInventory?

    private let deviceLibrary: any DeviceLibraryInspecting
    private let inventoryBuilder: ManagedDeviceLibraryInventoryBuilder
    private let deletionService: DeviceFileDeletionService
    private let safetyValidator: SafetyValidator
    private var filesBySubscriptionID: [UUID: [URL]]
    private var filesByEpisodeStemBySubscriptionID: [UUID: [String: URL]]
    private var conservativelyMatchedFilesByEpisodeIDBySubscriptionID: [UUID: [String: URL]]
    private var latestRefreshID: UUID?
    private var latestOtherAudioReviewID: UUID?
    private var inventoryTask: Task<(ManagedDeviceLibraryInventory, Bool), Error>?
    private var otherAudioReviewTask: Task<[URL], Error>?

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        fileSystem: any FileSystemOperating = LocalFileSystem(),
        safetyValidator: SafetyValidator = SafetyValidator()
    ) {
        self.deviceLibrary = deviceLibrary
        self.inventoryBuilder = ManagedDeviceLibraryInventoryBuilder(deviceLibrary: deviceLibrary)
        self.deletionService = DeviceFileDeletionService(
            fileSystem: fileSystem,
            safetyValidator: safetyValidator
        )
        self.safetyValidator = safetyValidator
        self.filesBySubscriptionID = [:]
        self.filesByEpisodeStemBySubscriptionID = [:]
        self.conservativelyMatchedFilesByEpisodeIDBySubscriptionID = [:]
        self.otherAudioFiles = []
        self.hasOtherAudioAvailable = false
        self.isReviewingOtherAudio = false
        self.otherAudioReviewInspectedFileCount = 0
        self.otherAudioReviewMessage = nil
        self.isRefreshingManagedInventory = false
        self.lastErrorMessage = nil
        self.managedInventory = nil
    }

    public func refresh(
        device: DeviceInfo?,
        subscriptions: [PodcastSubscription],
        episodes: [Episode] = []
    ) async {
        inventoryTask?.cancel()
        cancelOtherAudioReview(clearResults: true)
        hasOtherAudioAvailable = false
        let refreshID = UUID()
        latestRefreshID = refreshID

        guard let device else {
            filesBySubscriptionID = [:]
            filesByEpisodeStemBySubscriptionID = [:]
            conservativelyMatchedFilesByEpisodeIDBySubscriptionID = [:]
            managedInventory = nil
            isRefreshingManagedInventory = false
            lastErrorMessage = nil
            return
        }

        isRefreshingManagedInventory = true

        do {
            try safetyValidator.validateDevice(device)
            let inventoryBuilder = inventoryBuilder
            let deviceLibrary = deviceLibrary
            let task = Task.detached(priority: .userInitiated) {
                let inventory = try inventoryBuilder.makeInventory(
                    device: device,
                    subscriptions: subscriptions
                )
                let hasOtherAudio: Bool
                do {
                    hasOtherAudio = try deviceLibrary.containsSupportedAudioFile(
                        in: device.podcastDirectoryURL,
                        excluding: inventory.allManagedFileURLs
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // This optional hint must never prevent normal device inventory or sync.
                    hasOtherAudio = false
                }
                return (inventory, hasOtherAudio)
            }
            inventoryTask = task
            let (inventory, hasOtherAudio) = try await task.value
            guard latestRefreshID == refreshID else { return }

            managedInventory = inventory
            hasOtherAudioAvailable = hasOtherAudio
            filesBySubscriptionID = Dictionary(uniqueKeysWithValues: subscriptions.map {
                ($0.id, inventory.files(for: $0))
            })
            rebuildFileIndex(subscriptions: subscriptions, episodes: episodes)
            isRefreshingManagedInventory = false
            lastErrorMessage = nil
            inventoryTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard latestRefreshID == refreshID else { return }
            filesBySubscriptionID = [:]
            filesByEpisodeStemBySubscriptionID = [:]
            conservativelyMatchedFilesByEpisodeIDBySubscriptionID = [:]
            managedInventory = nil
            hasOtherAudioAvailable = false
            isRefreshingManagedInventory = false
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            inventoryTask = nil
        }
    }

    public func reviewOtherAudio(on device: DeviceInfo?) async {
        cancelOtherAudioReview(clearResults: true)
        guard let device else { return }
        guard managedInventory?.deviceID == device.id,
              managedInventory?.podcastDirectoryURL == device.podcastDirectoryURL.standardizedFileURL else {
            lastErrorMessage = "Wait for the device podcast inventory to finish before reviewing other audio."
            return
        }

        let reviewID = UUID()
        latestOtherAudioReviewID = reviewID
        isReviewingOtherAudio = true
        otherAudioReviewInspectedFileCount = 0
        otherAudioReviewMessage = nil
        lastErrorMessage = nil

        do {
            try safetyValidator.validateDevice(device)
            let deviceLibrary = deviceLibrary
            let managedFileURLs = managedInventory?.allManagedFileURLs ?? []
            let reportProgress: @Sendable (Int) -> Void = { [weak self] count in
                Task { @MainActor [weak self] in
                    guard self?.latestOtherAudioReviewID == reviewID else { return }
                    self?.otherAudioReviewInspectedFileCount = count
                }
            }
            let task = Task.detached(priority: .userInitiated) {
                let files = try deviceLibrary.recursiveFiles(
                    in: device.podcastDirectoryURL,
                    progress: reportProgress
                )
                try Task.checkCancellation()
                return Self.otherAudioFiles(in: files, excluding: managedFileURLs)
            }
            otherAudioReviewTask = task
            let reviewedFiles = try await task.value
            guard latestOtherAudioReviewID == reviewID else { return }

            otherAudioFiles = reviewedFiles
            hasOtherAudioAvailable = !reviewedFiles.isEmpty
            otherAudioReviewMessage = reviewedFiles.isEmpty ? "No other audio found." : nil
            lastErrorMessage = nil
            isReviewingOtherAudio = false
            otherAudioReviewTask = nil
            latestOtherAudioReviewID = nil
        } catch is CancellationError {
            guard latestOtherAudioReviewID == reviewID else { return }
            isReviewingOtherAudio = false
            otherAudioReviewTask = nil
            latestOtherAudioReviewID = nil
        } catch {
            guard latestOtherAudioReviewID == reviewID else { return }
            isReviewingOtherAudio = false
            otherAudioReviewTask = nil
            latestOtherAudioReviewID = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func cancelOtherAudioReview() {
        cancelOtherAudioReview(clearResults: false)
    }

    public func dismissOtherAudioResults() {
        cancelOtherAudioReview(clearResults: true)
    }

    public func cancelAllWork() {
        latestRefreshID = nil
        inventoryTask?.cancel()
        inventoryTask = nil
        isRefreshingManagedInventory = false
        cancelOtherAudioReview(clearResults: false)
    }

    public func files(for subscription: PodcastSubscription) -> [URL] {
        filesBySubscriptionID[subscription.id] ?? []
    }

    public func file(for episode: Episode) -> URL? {
        guard let subscriptionID = episode.subscriptionID else {
            return nil
        }

        let expectedFileStem = EpisodeFileName.fileStem(for: episode)
        return filesByEpisodeStemBySubscriptionID[subscriptionID]?[expectedFileStem]
            ?? conservativelyMatchedFilesByEpisodeIDBySubscriptionID[subscriptionID]?[episode.id]
    }

    public var hasOtherAudio: Bool {
        !otherAudioFiles.isEmpty
    }

    private func rebuildFileIndex(
        subscriptions: [PodcastSubscription],
        episodes: [Episode]
    ) {
        filesByEpisodeStemBySubscriptionID = filesBySubscriptionID.mapValues { files in
            var filesByStem: [String: URL] = [:]
            for file in files where filesByStem[file.deletingPathExtension().lastPathComponent] == nil {
                filesByStem[file.deletingPathExtension().lastPathComponent] = file
            }
            return filesByStem
        }

        conservativelyMatchedFilesByEpisodeIDBySubscriptionID = [:]
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let episodesBySubscriptionID = Dictionary(grouping: episodes.compactMap { episode -> (UUID, Episode)? in
            guard let subscriptionID = episode.subscriptionID else { return nil }
            return (subscriptionID, episode)
        }, by: \.0).mapValues { $0.map(\.1) }

        for (subscriptionID, subscriptionEpisodes) in episodesBySubscriptionID {
            guard let subscription = subscriptionsByID[subscriptionID] else { continue }
            let files = filesBySubscriptionID[subscriptionID] ?? []
            conservativelyMatchedFilesByEpisodeIDBySubscriptionID[subscriptionID] =
                EpisodeFileName.uniqueConservativeMatches(
                    in: files,
                    to: subscriptionEpisodes,
                    subscription: subscription
                )
        }
    }

    public func unmatchedFiles(
        for subscription: PodcastSubscription,
        episodes: [Episode]
    ) -> [URL] {
        let matchedFiles = Set(episodes.compactMap(file(for:)))
        return files(for: subscription).filter {
            !matchedFiles.contains($0)
        }
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

                try deletionService.deleteExplicitFile(at: standardizedURL, on: device)
                deletedURLs.insert(standardizedURL)
            }

            otherAudioFiles.removeAll { deletedURLs.contains($0.standardizedFileURL) }
            if otherAudioFiles.isEmpty {
                hasOtherAudioAvailable = false
                otherAudioReviewMessage = "No other audio found."
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    nonisolated private static func otherAudioFiles(
        in deviceFiles: [URL],
        excluding managedFileURLs: Set<URL>
    ) -> [URL] {
        deviceFiles
            .filter(DeviceAudioFile.isSupported)
            .filter { !managedFileURLs.contains($0.standardizedFileURL) }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
    }

    private func cancelOtherAudioReview(clearResults: Bool) {
        latestOtherAudioReviewID = nil
        otherAudioReviewTask?.cancel()
        otherAudioReviewTask = nil
        isReviewingOtherAudio = false
        otherAudioReviewInspectedFileCount = 0
        otherAudioReviewMessage = nil
        if clearResults {
            otherAudioFiles = []
        }
    }
}
