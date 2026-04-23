import AppKit
import SwiftUI
import SPodcastManagerCore
import SPodcastManagerUI

@main
struct SPodcastManagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = MainViewModel(
        store: JSONConfigurationStore(fileURL: JSONConfigurationStore.defaultFileURL())
    )

    var body: some Scene {
        WindowGroup("S Podcast Manager") {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About S Podcast Manager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "S Podcast Manager",
                            .credits: aboutCredits(),
                        ]
                    )
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .sPodcastManagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func aboutCredits() -> NSAttributedString {
        NSAttributedString(
            string: "\"S Podcast Manager\" is Steve's Podcast Manager.\n\"Spod\" is a British slang term.",
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
