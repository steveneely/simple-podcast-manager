import Combine
import Foundation
import SimplePodcastManagerCore
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    private var updaterController: SPUStandardUpdaterController?
    private let isInstalledApp: Bool
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
    private var hasCheckedForUpdatesThisLaunch = false

    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool

    init(bundle: Bundle = .main) {
        self.isInstalledApp = bundle.bundleURL.pathExtension == "app"
        self.updaterController = nil
        self.canCheckForUpdates = false
        self.automaticallyChecksForUpdates = false

        super.init()

        if isInstalledApp {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: self
            )
            updaterController = controller
            canCheckForUpdates = controller.updater.canCheckForUpdates
            automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        }

        canCheckForUpdatesObservation = updaterController?.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
                self?.checkForUpdatesAtStartupIfNeeded()
            }
        }

        automaticallyChecksForUpdatesObservation = updaterController?.updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                self?.checkForUpdatesAtStartupIfNeeded()
            }
        }
    }

    var checkForUpdatesHelpText: String {
        isInstalledApp
            ? "Check for app updates"
            : "Updates are only available in installed app builds."
    }

    func checkForUpdates() {
        guard let updaterController, updaterController.updater.canCheckForUpdates else {
            return
        }

        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else { return }

        updater.automaticallyChecksForUpdates = isEnabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        checkForUpdatesAtStartupIfNeeded()
    }

    private func checkForUpdatesAtStartupIfNeeded() {
        guard let updater = updaterController?.updater else { return }
        guard StartupUpdateCheckPolicy.shouldCheck(
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            canCheckForUpdates: updater.canCheckForUpdates,
            hasCheckedThisLaunch: hasCheckedForUpdatesThisLaunch
        ) else { return }

        hasCheckedForUpdatesThisLaunch = true
        updater.checkForUpdatesInBackground()
    }
}

extension AppUpdater: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }

        // Sparkle defers scheduled alerts for regular apps until their next activation.
        // A launch check should instead present an available update in this launch.
        updaterController?.checkForUpdates(nil)
    }
}
