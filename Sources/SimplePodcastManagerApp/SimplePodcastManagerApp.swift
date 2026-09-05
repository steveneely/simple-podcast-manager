import AppKit
import SwiftUI
import SimplePodcastManagerCore
import SimplePodcastManagerUI

@main
struct SimplePodcastManagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appUpdater = AppUpdater()
    @State private var appearancePreference = AppearancePreference.system
    @State private var viewModel = MainViewModel(
        store: JSONConfigurationStore(fileURL: JSONConfigurationStore.defaultFileURL())
    )

    var body: some Scene {
        WindowGroup("Simple Podcast Manager") {
            MainView(
                viewModel: viewModel,
                automaticallyChecksForUpdates: Binding(
                    get: { appUpdater.automaticallyChecksForUpdates },
                    set: { appUpdater.setAutomaticallyChecksForUpdates($0) }
                ),
                appearancePreference: Binding(
                    get: { appearancePreference },
                    set: { preference in
                        // AppKit semantic colors must see the new appearance before SwiftUI rebuilds the panels.
                        applyAppearance(preference)
                        appearancePreference = preference
                    }
                )
            )
            .onAppear {
                applyAppearance(appearancePreference)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Podcast…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerAddPodcast, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Import Podcasts…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerImportSubscriptions, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Export Podcasts…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerExportSubscriptions, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Simple Podcast Manager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: aboutPanelOptions()
                    )
                }

                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
                .help(appUpdater.checkForUpdatesHelpText)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Simple Podcast Manager",
            .applicationVersion: aboutApplicationVersion(),
            .credits: aboutCredits(),
        ]

        if let buildDetail = aboutBuildDetail() {
            options[.version] = buildDetail
        }

        return options
    }

    private func applyAppearance(_ preference: AppearancePreference) {
        NSApplication.shared.appearance = ApplicationAppearance.appearance(for: preference)
    }

    private func aboutApplicationVersion() -> String {
        let bundle = Bundle.main
        let releaseTag = bundle.object(forInfoDictionaryKey: "SPMReleaseTag") as? String

        if let releaseTag {
            return AppReleaseIdentity.displayName(forReleaseTag: releaseTag)
        }

        return "Local build"
    }

    private func aboutBuildDetail() -> String? {
        let bundle = Bundle.main
        let releaseTag = bundle.object(forInfoDictionaryKey: "SPMReleaseTag") as? String
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if releaseTag != nil {
            return buildVersion.map { "build \($0)" }
        }

        var details: [String] = []
        if let shortVersion, let buildVersion {
            details.append("\(shortVersion), build \(buildVersion)")
        } else if let shortVersion {
            details.append(shortVersion)
        } else if let buildVersion {
            details.append("build \(buildVersion)")
        }

        if let gitRevision = gitRevision() {
            details.append("git \(gitRevision)")
        }

        return details.isEmpty ? nil : details.joined(separator: ", ")
    }

    private func gitRevision() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--short", "HEAD"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let revision = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return revision?.isEmpty == false ? revision : nil
    }

    private func aboutCredits() -> NSAttributedString {
        return NSAttributedString(
            string: "A simple macOS app for subscribing via RSS, downloading episodes, syncing them to an MP3 player, and deleting older podcasts you no longer want on the device.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
