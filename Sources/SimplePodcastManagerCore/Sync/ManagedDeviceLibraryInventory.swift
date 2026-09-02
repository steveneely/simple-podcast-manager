import Foundation

public struct ManagedDeviceLibraryInventory: Sendable {
    public let deviceID: String
    public let podcastDirectoryURL: URL
    public let subscriptionIDs: Set<UUID>
    private let managedDirectoryURLsBySubscriptionID: [UUID: URL]
    private let filesBySubscriptionID: [UUID: [URL]]

    public init(
        device: DeviceInfo,
        subscriptions: [FeedSubscription],
        managedDirectoryURLsBySubscriptionID: [UUID: URL],
        filesBySubscriptionID: [UUID: [URL]]
    ) {
        self.deviceID = device.id
        self.podcastDirectoryURL = device.podcastDirectoryURL.standardizedFileURL
        self.subscriptionIDs = Set(subscriptions.map(\.id))
        self.managedDirectoryURLsBySubscriptionID = managedDirectoryURLsBySubscriptionID
        self.filesBySubscriptionID = filesBySubscriptionID
    }

    public func canBeUsed(on device: DeviceInfo, subscriptions: [FeedSubscription]) -> Bool {
        deviceID == device.id
            && podcastDirectoryURL == device.podcastDirectoryURL.standardizedFileURL
            && subscriptionIDs == Set(subscriptions.map(\.id))
    }

    public func managedDirectoryURL(for subscription: FeedSubscription, on device: DeviceInfo) -> URL {
        managedDirectoryURLsBySubscriptionID[subscription.id]
            ?? device.podcastDirectoryURL.appendingPathComponent(
                EpisodeFileName.directoryName(for: subscription),
                isDirectory: true
            )
    }

    public func files(for subscription: FeedSubscription) -> [URL] {
        filesBySubscriptionID[subscription.id] ?? []
    }

    public var allManagedFileURLs: Set<URL> {
        Set(filesBySubscriptionID.values.joined().map(\.standardizedFileURL))
    }
}

public struct ManagedDeviceLibraryInventoryBuilder: Sendable {
    private let deviceLibrary: any DeviceLibraryInspecting
    private let managedDirectoryResolver: ManagedDirectoryResolver

    public init(
        deviceLibrary: any DeviceLibraryInspecting = FileSystemDeviceLibrary(),
        managedDirectoryResolver: ManagedDirectoryResolver = ManagedDirectoryResolver()
    ) {
        self.deviceLibrary = deviceLibrary
        self.managedDirectoryResolver = managedDirectoryResolver
    }

    public func makeInventory(
        device: DeviceInfo,
        subscriptions: [FeedSubscription]
    ) throws -> ManagedDeviceLibraryInventory {
        try Task.checkCancellation()
        let candidateDirectories = try deviceLibrary.directories(in: device.podcastDirectoryURL)
        var managedDirectoryURLsBySubscriptionID: [UUID: URL] = [:]
        var filesBySubscriptionID: [UUID: [URL]] = [:]

        for subscription in subscriptions {
            try Task.checkCancellation()
            let managedDirectoryURL = managedDirectoryResolver.managedDirectoryURL(
                for: subscription,
                on: device,
                candidateDirectories: candidateDirectories
            )
            let files = try deviceLibrary.files(in: managedDirectoryURL)
                .filter { EpisodeFileName.isManagedEpisodeFile($0, for: subscription) }
            managedDirectoryURLsBySubscriptionID[subscription.id] = managedDirectoryURL
            filesBySubscriptionID[subscription.id] = Self.sortFiles(files)
        }

        return ManagedDeviceLibraryInventory(
            device: device,
            subscriptions: subscriptions,
            managedDirectoryURLsBySubscriptionID: managedDirectoryURLsBySubscriptionID,
            filesBySubscriptionID: filesBySubscriptionID
        )
    }

    private static func sortFiles(_ files: [URL]) -> [URL] {
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
}
