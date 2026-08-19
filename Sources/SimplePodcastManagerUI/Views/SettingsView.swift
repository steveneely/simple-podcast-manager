import AppKit
import SwiftUI
import SimplePodcastManagerCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
    @State private var appearancePreference: AppearancePreference
    @State private var allowsInsecureEpisodeDownloads: Bool
    @State private var podcastDirectoryPath: String
    @State private var automaticallyChecksForUpdates: Bool
    @State private var errorMessage: String?
    @State private var isShowingCreateFolderConfirmation = false
    @State private var pendingSave: PendingSave?
    @State private var hasSettledAppearancePreference = false
    private let selectedDeviceName: String?
    private let selectedDeviceRootURL: URL?
    private let savedAppearancePreference: AppearancePreference
    private let shouldConfirmPodcastDirectoryCreation: (String?) throws -> Bool
    private let onSave: (AppSettings, String?) throws -> Void
    private let onAppearancePreferencePreview: (AppearancePreference) -> Void
    private let onAutomaticallyChecksForUpdatesChange: (Bool) -> Void
    private let onBackUpAppData: () -> Void
    private let onRestoreAppData: () -> Void
    private let showsUpdateSettings: Bool

    private struct PendingSave {
        var settings: AppSettings
        var podcastDirectoryPath: String?
        var automaticallyChecksForUpdates: Bool
    }

    public init(
        settings: AppSettings,
        selectedDeviceName: String? = nil,
        selectedDeviceRootURL: URL? = nil,
        podcastDirectoryPath: String? = nil,
        automaticallyChecksForUpdates: Bool? = nil,
        shouldConfirmPodcastDirectoryCreation: @escaping (String?) throws -> Bool = { _ in false },
        onSave: @escaping (AppSettings, String?) throws -> Void,
        onAppearancePreferencePreview: @escaping (AppearancePreference) -> Void = { _ in },
        onAutomaticallyChecksForUpdatesChange: @escaping (Bool) -> Void = { _ in },
        onBackUpAppData: @escaping () -> Void = {},
        onRestoreAppData: @escaping () -> Void = {}
    ) {
        self._ffmpegExecutablePath = State(initialValue: settings.ffmpegExecutablePath ?? "")
        self._appearancePreference = State(initialValue: settings.appearancePreference)
        self._allowsInsecureEpisodeDownloads = State(initialValue: settings.allowsInsecureEpisodeDownloads)
        self._podcastDirectoryPath = State(initialValue: podcastDirectoryPath ?? DevicePodcastConfiguration.defaultPodcastDirectoryPath)
        self._automaticallyChecksForUpdates = State(initialValue: automaticallyChecksForUpdates ?? false)
        self._errorMessage = State(initialValue: nil)
        self.selectedDeviceName = selectedDeviceName
        self.selectedDeviceRootURL = selectedDeviceRootURL
        self.savedAppearancePreference = settings.appearancePreference
        self.shouldConfirmPodcastDirectoryCreation = shouldConfirmPodcastDirectoryCreation
        self.onSave = onSave
        self.onAppearancePreferencePreview = onAppearancePreferencePreview
        self.onAutomaticallyChecksForUpdatesChange = onAutomaticallyChecksForUpdatesChange
        self.onBackUpAppData = onBackUpAppData
        self.onRestoreAppData = onRestoreAppData
        self.showsUpdateSettings = automaticallyChecksForUpdates != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(
                    title: "Appearance",
                    detail: "Choose whether the app follows macOS, always uses light mode, or always uses dark mode."
                ) {
                    Picker("Appearance", selection: $appearancePreference) {
                        Text("System").tag(AppearancePreference.system)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Dark").tag(AppearancePreference.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                LabeledField(
                    title: "ffmpeg Path",
                    detail: "Optional. Needed only to convert non-MP3 podcast audio."
                ) {
                    chooserRow(
                        value: ffmpegExecutablePath.isEmpty ? "Not set" : ffmpegExecutablePath,
                        buttonTitle: "Choose…",
                        clearTitle: ffmpegExecutablePath.isEmpty ? nil : "Clear"
                    ) {
                        chooseFFmpegExecutable()
                    } onClear: {
                        ffmpegExecutablePath = ""
                    }
                }

                LabeledField(
                    title: "Insecure Downloads",
                    detail: "HTTPS is always tried first. HTTP downloads are unencrypted and could be intercepted or changed in transit."
                ) {
                    Toggle(
                        "Always allow HTTP episode downloads",
                        isOn: $allowsInsecureEpisodeDownloads
                    )
                    .toggleStyle(.checkbox)
                }

                LabeledField(
                    title: "Device Podcast Folder",
                    detail: selectedDeviceName.map { "Choose where podcasts are saved on \($0). Defaults to \"music\"." }
                        ?? "Connect a device to choose where its podcasts are saved. Defaults to \"music\"."
                ) {
                    chooserRow(
                        value: podcastDirectoryPath,
                        buttonTitle: "Choose Folder…",
                        clearTitle: nil
                    ) {
                        choosePodcastDirectory()
                    } onClear: {}
                    .disabled(selectedDeviceName == nil)
                }

                if showsUpdateSettings {
                    LabeledField(title: "Updates") {
                        Toggle(
                            "Check for updates on startup",
                            isOn: $automaticallyChecksForUpdates
                        )
                        .toggleStyle(.checkbox)
                    }
                }

                LabeledField(title: "App Data") {
                    HStack(spacing: 8) {
                        Button("Back Up…", systemImage: "archivebox") {
                            onBackUpAppData()
                        }

                        Button("Restore…", systemImage: "arrow.counterclockwise") {
                            onRestoreAppData()
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

            }

            HStack {
                Spacer()

                Button("Cancel") {
                    restoreSavedAppearancePreference()
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .alert("Create Podcast Folder?", isPresented: $isShowingCreateFolderConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingSave = nil
            }
            Button("Create Folder") {
                guard let pendingSave else { return }
                performSave(pendingSave)
            }
        } message: {
            Text(createFolderConfirmationMessage)
        }
        .onChange(of: appearancePreference) { _, preference in
            onAppearancePreferencePreview(preference)
        }
        .onDisappear {
            restoreSavedAppearancePreference()
        }
    }

    private func chooserRow(
        value: String,
        buttonTitle: String,
        clearTitle: String?,
        onChoose: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .stroke(Color(nsColor: .separatorColor))
                )

            Button(buttonTitle, action: onChoose)

            if let clearTitle {
                Button(clearTitle, action: onClear)
            }
        }
    }

    private var createFolderConfirmationMessage: String {
        let folder = pendingSave?.podcastDirectoryPath ?? podcastDirectoryPath
        let device = selectedDeviceName ?? "the selected device"
        return "The folder \"\(folder)\" does not exist on \(device). Create it and save this device setting?"
    }

    private func save() {
        let pendingSave = PendingSave(
            settings: AppSettings(
                ffmpegExecutablePath: ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                appearancePreference: appearancePreference,
                allowsInsecureEpisodeDownloads: allowsInsecureEpisodeDownloads
            ),
            podcastDirectoryPath: selectedDeviceName == nil ? nil : podcastDirectoryPath,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates
        )

        do {
            if try shouldConfirmPodcastDirectoryCreation(pendingSave.podcastDirectoryPath) {
                self.pendingSave = pendingSave
                isShowingCreateFolderConfirmation = true
                return
            }

            performSave(pendingSave)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performSave(_ pendingSave: PendingSave) {
        do {
            try onSave(pendingSave.settings, pendingSave.podcastDirectoryPath)
            if showsUpdateSettings {
                onAutomaticallyChecksForUpdatesChange(pendingSave.automaticallyChecksForUpdates)
            }
            hasSettledAppearancePreference = true
            self.pendingSave = nil
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restoreSavedAppearancePreference() {
        guard !hasSettledAppearancePreference else { return }

        onAppearancePreferencePreview(savedAppearancePreference)
        hasSettledAppearancePreference = true
    }

    private func chooseFFmpegExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose ffmpeg"
        panel.prompt = "Choose"
        panel.message = "Select the ffmpeg executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let currentURL = ffmpegExecutablePath.isEmpty ? URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true) : URL(fileURLWithPath: ffmpegExecutablePath).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: currentURL.path) {
            panel.directoryURL = currentURL
        }

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        ffmpegExecutablePath = selectedURL.path
        errorMessage = nil
    }

    private func choosePodcastDirectory() {
        guard let selectedDeviceRootURL else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Podcast Folder"
        panel.prompt = "Choose"
        panel.message = "Choose a folder on \(selectedDeviceName ?? "the selected device")."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = selectedDeviceRootURL

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        do {
            podcastDirectoryPath = try Self.relativeDevicePath(for: selectedURL, rootURL: selectedDeviceRootURL)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func relativeDevicePath(for selectedURL: URL, rootURL: URL) throws -> String {
        let rootURL = rootURL.standardizedFileURL
        let selectedURL = selectedURL.standardizedFileURL
        let rootPath = rootURL.path
        let selectedPath = selectedURL.path

        guard selectedPath.hasPrefix(rootPath + "/") else {
            throw DevicePodcastConfigurationError.invalidPodcastDirectoryPath(selectedPath)
        }

        let relativePath = String(selectedPath.dropFirst(rootPath.count + 1))
        return try DevicePodcastConfiguration.normalizedRelativeDirectoryPath(relativePath)
    }
}
