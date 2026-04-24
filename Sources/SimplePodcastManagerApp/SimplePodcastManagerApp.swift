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
            CommandGroup(replacing: .appInfo) {
                Button("About Simple Podcast Manager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Simple Podcast Manager",
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

    private func aboutCredits() -> NSAttributedString {
        NSAttributedString(
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
