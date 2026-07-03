import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController?
    private let isInstalledApp: Bool
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    @Published private(set) var canCheckForUpdates: Bool

    init(bundle: Bundle = .main) {
        self.isInstalledApp = bundle.bundleURL.pathExtension == "app"

        if isInstalledApp {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.updaterController = controller
            self.canCheckForUpdates = controller.updater.canCheckForUpdates
        } else {
            self.updaterController = nil
            self.canCheckForUpdates = false
        }

        super.init()

        canCheckForUpdatesObservation = updaterController?.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
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
}
