import AppKit
import OSLog
import SimplePodcastManagerCore
import UserNotifications

@MainActor
public protocol SyncCompletionNotifying {
    func prepareForSync() async
    func syncSucceeded(result: SyncResult) async
}

/// Notification failures must never change the outcome of a device sync.
@MainActor
public final class SyncCompletionNotifier: SyncCompletionNotifying {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SimplePodcastManager", category: "SyncNotifications")
    private let isAppActive: () -> Bool
    private let requestAuthorization: () async throws -> Bool
    private let currentAuthorization: () async -> Bool
    private let postNotification: (SyncResult) async throws -> Void

    public convenience init() {
        self.init(
            isAppActive: {
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let currentPID = ProcessInfo.processInfo.processIdentifier
                let appKitIsActive = NSApplication.shared.isActive
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "SimplePodcastManager", category: "SyncNotifications")
                    .notice("Sync focus check; frontmost PID: \(frontmostPID ?? -1), current PID: \(currentPID), AppKit active: \(appKitIsActive)")
                // Compare the actual frontmost process: AppKit's activation flag
                // can lag a focus change while the sync sheet is completing.
                return Self.isAppFrontmost(
                    frontmostProcessID: frontmostPID,
                    currentProcessID: currentPID,
                    appKitIsActive: appKitIsActive
                )
            },
            requestAuthorization: {
                // UserNotifications requires an application bundle. Do not access
                // its singleton from swift run or the command-line test runner.
                guard Bundle.main.bundleURL.pathExtension == "app",
                      Bundle.main.bundleIdentifier != nil else { return false }
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            },
            currentAuthorization: {
                guard Bundle.main.bundleURL.pathExtension == "app",
                      Bundle.main.bundleIdentifier != nil else { return false }
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                return settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            },
            postNotification: { result in
                let request = Self.makeNotificationRequest(result: result)
                try await UNUserNotificationCenter.current().add(request)
            }
        )
    }

    init(
        isAppActive: @escaping () -> Bool,
        requestAuthorization: @escaping () async throws -> Bool,
        currentAuthorization: @escaping () async -> Bool,
        postNotification: @escaping (SyncResult) async throws -> Void
    ) {
        self.isAppActive = isAppActive
        self.requestAuthorization = requestAuthorization
        self.currentAuthorization = currentAuthorization
        self.postNotification = postNotification
    }

    static func makeNotificationRequest(result: SyncResult) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Sync complete"
        let summary = summary(for: result)
        content.body = summary.isEmpty ? "" : "\n\(summary)"
        content.sound = UNNotificationSound.default
        return UNNotificationRequest(
            identifier: "sync-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }

    static func summary(for result: SyncResult) -> String {
        var parts: [String] = []
        if result.copiedCount > 0 {
            let noun = result.copiedCount == 1 ? "episode" : "episodes"
            parts.append("\(result.copiedCount) \(noun) copied")
        }
        if result.deletedCount > 0 {
            let noun = result.deletedCount == 1 ? "episode" : "episodes"
            parts.append("\(result.deletedCount) \(noun) deleted")
        }
        // Skips also include episodes selected for removal. Only the planner's
        // verified existing-copy skips mean an episode remains on the device.
        let alreadyOnDeviceCount = result.completedActions.filter { action in
            guard case .skip(let reason) = action else { return false }
            return reason.hasPrefix("Already on device: ")
        }.count
        if alreadyOnDeviceCount > 0 {
            parts.append("\(alreadyOnDeviceCount) already on device")
        }
        if result.updatedPlaylistCount > 0 {
            let noun = result.updatedPlaylistCount == 1 ? "playlist" : "playlists"
            parts.append("\(result.updatedPlaylistCount) \(noun) updated")
        }
        if result.deletedPlaylistCount > 0 {
            let noun = result.deletedPlaylistCount == 1 ? "playlist" : "playlists"
            parts.append("\(result.deletedPlaylistCount) \(noun) deleted")
        }
        if result.ejected {
            parts.append("Device ejected.")
        }
        return parts.map { "• \($0)" }.joined(separator: "\n")
    }

    static func isAppFrontmost(
        frontmostProcessID: Int32?,
        currentProcessID: Int32,
        appKitIsActive: Bool
    ) -> Bool {
        frontmostProcessID.map { $0 == currentProcessID } ?? appKitIsActive
    }

    public func prepareForSync() async {
        do {
            let isAuthorized = try await requestAuthorization()
            logger.notice("Sync notification authorization granted: \(isAuthorized)")
        } catch {
            logger.error("Sync notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func syncSucceeded(result: SyncResult) async {
        // Settings can change during a long sync. Check again without prompting,
        // then read focus after the asynchronous settings lookup has completed.
        let isAuthorized = await currentAuthorization()
        let active = isAppActive()
        logger.notice("Sync succeeded; notification authorization: \(isAuthorized), app active: \(active)")
        guard isAuthorized, !active else { return }
        do {
            try await postNotification(result)
            logger.notice("Sync completion notification submitted")
        } catch {
            logger.error("Sync completion notification submission failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
