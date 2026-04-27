import AppKit
import SwiftUI
import SimplePodcastManagerCore
import SimplePodcastManagerUI

@main
struct SimplePodcastManagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = MainViewModel(
        store: JSONConfigurationStore(fileURL: JSONConfigurationStore.defaultFileURL())
    )

    var body: some Scene {
        WindowGroup("Simple Podcast Manager") {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerCheckForUpdates, object: nil)
                }

                Divider()

                Button("Export App Data…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerExportAppData, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import App Data…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerImportAppData, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Simple Podcast Manager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Simple Podcast Manager",
                            .version: aboutVersion(),
                            .credits: aboutCredits(),
                        ]
                    )
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .simplePodcastManagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func aboutVersion() -> String {
        let bundle = Bundle.main
        let releaseTag = bundle.object(forInfoDictionaryKey: "SPMReleaseTag") as? String
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let releaseTag, let shortVersion, let buildVersion {
            let displayTag = AppReleaseIdentity.displayName(forReleaseTag: releaseTag)
            return "\(displayTag) (\(shortVersion), build \(buildVersion))"
        }

        if let releaseTag {
            return AppReleaseIdentity.displayName(forReleaseTag: releaseTag)
        }

        if let shortVersion, let buildVersion {
            return "\(shortVersion) (build \(buildVersion))"
        }

        return shortVersion ?? "Local build"
    }

    private func aboutCredits() -> NSAttributedString {
        var credits = "A simple macOS app for subscribing via RSS, downloading episodes, syncing them to an MP3 player, and deleting older podcasts you no longer want on the device."
        if Bundle.main.url(forResource: "ffmpeg", withExtension: nil) != nil {
            credits += "\n\nIncludes FFmpeg for audio conversion. FFmpeg is licensed separately; see the third-party notices included with this release."
        }

        return NSAttributedString(
            string: credits,
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
