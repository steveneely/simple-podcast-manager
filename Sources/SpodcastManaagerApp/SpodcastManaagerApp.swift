import AppKit
import SwiftUI
import SpodcastManaagerCore
import SpodcastManaagerUI

@main
struct SpodcastManaagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = MainViewModel(
        store: JSONConfigurationStore(fileURL: JSONConfigurationStore.defaultFileURL())
    )

    var body: some Scene {
        WindowGroup("Spodcast Manaager") {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Spodcast Manaager") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Spodcast Manaager",
                            .credits: aboutCredits(),
                        ]
                    )
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .spodcastManaagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func aboutCredits() -> NSAttributedString {
        NSAttributedString(
            string: "\"Spodcast Manager\" is Steve's Podcast Manager.\n\"Spod\" is a British slang term.",
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
