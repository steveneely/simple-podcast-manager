import AppKit
import SwiftUI
import SimplePodcastManagerCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SettingsDraft
    @State private var errorMessage: String?
    @State private var isShowingCreateFolderConfirmation = false
    @State private var folderPendingCreation: DeviceFolderKind = .podcast
    @State private var isShowingPodcastMigrationConfirmation = false
    @State private var pendingSave: PendingSave?
    @State private var hasSettledAppearancePreference = false
    private let selectedDeviceName: String?
    private let selectedDeviceRootURL: URL?
    private let savedAppearancePreference: AppearancePreference
    private let shouldConfirmPodcastDirectoryCreation: (String?) throws -> Bool
    private let shouldConfirmPlaylistDirectoryCreation: (String?) throws -> Bool
    private let makePodcastDirectoryMigrationPlan: (String?) throws -> DevicePodcastDirectoryMigrationPlan?
    private let onSave: (AppSettings, String?, String?, DevicePodcastDirectoryMigrationPlan?) throws -> Void
    private let onAppearancePreferencePreview: (AppearancePreference) -> Void
    private let onAutomaticallyChecksForUpdatesChange: (Bool) -> Void
    private let onBackUpAppData: () -> Void
    private let canRestoreAppData: Bool
    private let onRestoreAppData: () -> Void
    private let showsUpdateSettings: Bool

    private struct PendingSave {
        var settings: AppSettings
        var podcastDirectoryPath: String?
        var playlistDirectoryPath: String?
        var automaticallyChecksForUpdates: Bool
        var migrationPlan: DevicePodcastDirectoryMigrationPlan?
    }

    public init(
        settings: AppSettings,
        selectedDeviceName: String? = nil,
        selectedDeviceRootURL: URL? = nil,
        podcastDirectoryPath: String? = nil,
        playlistDirectoryPath: String? = nil,
        automaticallyChecksForUpdates: Bool? = nil,
        shouldConfirmPodcastDirectoryCreation: @escaping (String?) throws -> Bool = { _ in false },
        shouldConfirmPlaylistDirectoryCreation: @escaping (String?) throws -> Bool = { _ in false },
        makePodcastDirectoryMigrationPlan: @escaping (String?) throws -> DevicePodcastDirectoryMigrationPlan? = { _ in nil },
        onSave: @escaping (AppSettings, String?, String?, DevicePodcastDirectoryMigrationPlan?) throws -> Void,
        onAppearancePreferencePreview: @escaping (AppearancePreference) -> Void = { _ in },
        onAutomaticallyChecksForUpdatesChange: @escaping (Bool) -> Void = { _ in },
        onBackUpAppData: @escaping () -> Void = {},
        canRestoreAppData: Bool = true,
        onRestoreAppData: @escaping () -> Void = {}
    ) {
        self._draft = State(initialValue: SettingsDraft(
            settings: settings,
            podcastDirectoryPath: podcastDirectoryPath,
            playlistDirectoryPath: playlistDirectoryPath,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates
        ))
        self._errorMessage = State(initialValue: nil)
        self.selectedDeviceName = selectedDeviceName
        self.selectedDeviceRootURL = selectedDeviceRootURL
        self.savedAppearancePreference = settings.appearancePreference
        self.shouldConfirmPodcastDirectoryCreation = shouldConfirmPodcastDirectoryCreation
        self.shouldConfirmPlaylistDirectoryCreation = shouldConfirmPlaylistDirectoryCreation
        self.makePodcastDirectoryMigrationPlan = makePodcastDirectoryMigrationPlan
        self.onSave = onSave
        self.onAppearancePreferencePreview = onAppearancePreferencePreview
        self.onAutomaticallyChecksForUpdatesChange = onAutomaticallyChecksForUpdatesChange
        self.onBackUpAppData = onBackUpAppData
        self.canRestoreAppData = canRestoreAppData
        self.onRestoreAppData = onRestoreAppData
        self.showsUpdateSettings = automaticallyChecksForUpdates != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: $draft.selectedPage) {
                    ForEach(SettingsPage.allCases) { page in
                        Label(page.rawValue, systemImage: page.systemImage)
                            .listItemTint(.preferred(.primary))
                            .tag(page)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Settings sections")
                .frame(width: 170)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.selectedPage.rawValue)
                                .font(.title2)
                                .fontWeight(.semibold)
                            if draft.selectedPage == .device {
                                if let selectedDeviceName, selectedDeviceRootURL != nil {
                                    Label(selectedDeviceName, systemImage: "externaldrive")
                                        .font(.subheadline)
                                } else {
                                    Text("Connect a device to choose its podcast and playlist folders.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        pageContent
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(draft.selectedPage)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        restoreSavedAppearancePreference()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.hasChanges)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 760, idealWidth: 800, maxWidth: .infinity,
               minHeight: 560, idealHeight: 620, maxHeight: .infinity)
        .alert(createFolderConfirmationTitle, isPresented: $isShowingCreateFolderConfirmation) {
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
        .sheet(isPresented: $isShowingPodcastMigrationConfirmation) {
            if let plan = pendingSave?.migrationPlan {
                PodcastDirectoryMigrationReviewView(
                    plan: plan,
                    onCancel: {
                        pendingSave = nil
                        isShowingPodcastMigrationConfirmation = false
                    },
                    onLeaveFiles: {
                        guard var pendingSave else { return }
                        pendingSave.migrationPlan = nil
                        isShowingPodcastMigrationConfirmation = false
                        continueSavingWithoutMigration(pendingSave)
                    },
                    onMoveFiles: {
                        guard let pendingSave else { return }
                        isShowingPodcastMigrationConfirmation = false
                        performSave(pendingSave)
                    }
                )
            }
        }
        .onChange(of: draft.settings.appearancePreference) { _, preference in
            onAppearancePreferencePreview(preference)
        }
        .onDisappear {
            restoreSavedAppearancePreference()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch draft.selectedPage {
        case .general: generalSettings
        case .downloads: downloadSettings
        case .device: deviceSettings
        case .advanced: advancedSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsField(
                title: "Appearance",
                detail: "Choose whether the app follows macOS, always uses light mode, or always uses dark mode."
            ) {
                Picker("Appearance", selection: $draft.settings.appearancePreference) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280, alignment: .leading)
            }

            SettingsField(
                title: "Inactive Podcasts",
                detail: "Shows an orange Inactive label beside podcasts that have not published recently."
            ) {
                Picker("Inactive Podcasts", selection: $draft.settings.inactivePodcastThreshold) {
                    Text("Off").tag(InactivePodcastThreshold.off)
                    Text("After 3 months").tag(InactivePodcastThreshold.threeMonths)
                    Text("After 6 months").tag(InactivePodcastThreshold.sixMonths)
                    Text("After 1 year").tag(InactivePodcastThreshold.oneYear)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if showsUpdateSettings {
                SettingsField(title: "Updates") {
                    Toggle("Check for updates on startup", isOn: $draft.automaticallyChecksForUpdates)
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var downloadSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsField(
                title: "Automatic Downloads",
                detail: "Downloads new episodes automatically after podcasts refresh. The selected limit applies separately to each included podcast."
            ) {
                Picker("Automatic Downloads", selection: $draft.settings.automaticDownloadLimit) {
                    Text("Off").tag(AutomaticDownloadLimit.off)
                    Text("Latest 1").tag(AutomaticDownloadLimit.latest1)
                    Text("Latest 2").tag(AutomaticDownloadLimit.latest2)
                    Text("Latest 3").tag(AutomaticDownloadLimit.latest3)
                    Text("All new").tag(AutomaticDownloadLimit.allNew)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsSection(title: "MP3 Metadata") {
                SettingsField(
                    title: "MP3 Episode Titles",
                    detail: "Adds the date in MM.dd format, such as 08.11 Original Title. Applies to new downloads only."
                ) {
                    Toggle(
                        "Prefix with publication date",
                        isOn: $draft.settings.prefixesPublicationDateInEpisodeTitles
                    )
                    .toggleStyle(.checkbox)
                }

                SettingsField(
                    title: "MP3 Genre",
                    detail: "Writes this value to the MP3’s ID3 genre field. Leave blank to omit it. Applies to new downloads only."
                ) {
                    TextField("", text: $draft.settings.mp3Genre)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .accessibilityLabel("MP3 Genre")
                }
            }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsField(
                title: "FFmpeg Path",
                detail: "FFmpeg is not included with the app. Install it and select its executable to convert non-MP3 podcast audio."
            ) {
                chooserRow(
                    value: draft.ffmpegExecutablePath.isEmpty ? nil : draft.ffmpegExecutablePath,
                    buttonTitle: "Choose…",
                    clearTitle: draft.ffmpegExecutablePath.isEmpty ? nil : "Clear"
                ) {
                    chooseFFmpegExecutable()
                } onClear: {
                    draft.ffmpegExecutablePath = ""
                }
            }

            SettingsField(
                title: "Insecure Downloads",
                detail: "HTTPS is always tried first. HTTP audio and artwork are unencrypted and could be intercepted or changed in transit."
            ) {
                Toggle(
                    "Always allow HTTP podcast downloads",
                    isOn: $draft.settings.allowsInsecureDownloads
                )
                .toggleStyle(.checkbox)
            }

            SettingsSection(title: "App Data") {
                appDataSettings
            }
        }
    }

    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsField(
                title: "Device Cleanup",
                detail: "Suggests deleting episodes beyond the selected number per podcast. You can review and keep any episode before syncing."
            ) {
                Picker("Device Cleanup", selection: cleanupEpisodeLimitSelection) {
                    Text("Off").tag(Int?.none)
                    ForEach(DeviceCleanupPolicy.allowedMaximumEpisodesPerPodcast, id: \.self) { count in
                        Text("Keep \(count) episodes").tag(Int?.some(count))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsSection(title: "Device Folders") {
                SettingsField(
                    title: "Device Podcast Folder",
                    detail: selectedDeviceName.map { "Choose where podcasts are saved on \($0). Defaults to \"music\"." }
                ) {
                    chooserRow(
                        value: draft.podcastDirectoryPath,
                        buttonTitle: "Choose Folder…",
                        clearTitle: nil,
                        isChoosingEnabled: selectedDeviceRootURL != nil
                    ) {
                        choosePodcastDirectory()
                    } onClear: {}
                }

                SettingsField(
                    title: "Device Playlist Folder",
                    detail: selectedDeviceName.map { _ in "Choose where playlists are saved. Some devices require playlists to be stored in a separate folder." }
                ) {
                    chooserRow(
                        value: draft.playlistDirectoryPath,
                        buttonTitle: "Choose Folder…",
                        clearTitle: nil,
                        isChoosingEnabled: selectedDeviceRootURL != nil
                    ) {
                        choosePlaylistDirectory()
                    } onClear: {}
                }
            }
        }
    }

    private var appDataSettings: some View {
        HStack(spacing: 8) {
            Button("Back Up…", systemImage: "archivebox", action: onBackUpAppData)
            Spacer(minLength: 32)
            Button("Restore…", systemImage: "arrow.counterclockwise", action: onRestoreAppData)
                .disabled(!canRestoreAppData)
                .help(canRestoreAppData
                    ? "Restore podcasts, settings, and episode history"
                    : "Wait for refreshes, downloads, and sync to finish before restoring app data")
        }
    }

    private func chooserRow(
        value: String?,
        buttonTitle: String,
        clearTitle: String?,
        isChoosingEnabled: Bool = true,
        onChoose: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(value ?? "Not set")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .frame(width: 240, alignment: .leading)
                .help(value ?? "Not set")
                .contentShape(Rectangle())
                .contextMenu {
                    if let value {
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .stroke(Color(nsColor: .separatorColor))
                )

            Button(buttonTitle, action: onChoose)
                .disabled(!isChoosingEnabled)

            if let clearTitle {
                Button(clearTitle, action: onClear)
            }
        }
    }

    private var createFolderConfirmationMessage: String {
        let folder = switch folderPendingCreation {
        case .podcast:
            pendingSave?.podcastDirectoryPath ?? draft.podcastDirectoryPath
        case .playlist:
            pendingSave?.playlistDirectoryPath ?? draft.playlistDirectoryPath
        }
        let device = selectedDeviceName ?? "the selected device"
        return "The folder \"\(folder)\" does not exist on \(device). Create it and save this device setting?"
    }

    private var createFolderConfirmationTitle: String {
        switch folderPendingCreation {
        case .podcast: "Create Podcast Folder?"
        case .playlist: "Create Playlist Folder?"
        }
    }

    private func save() {
        guard draft.hasChanges else { return }
        let pendingSave = PendingSave(
            settings: draft.settingsForSaving,
            podcastDirectoryPath: selectedDeviceName == nil ? nil : draft.podcastDirectoryPath,
            playlistDirectoryPath: selectedDeviceName == nil ? nil : draft.playlistDirectoryPath,
            automaticallyChecksForUpdates: draft.automaticallyChecksForUpdates,
            migrationPlan: nil
        )

        do {
            var pendingSave = pendingSave
            if let migrationPlan = try makePodcastDirectoryMigrationPlan(pendingSave.podcastDirectoryPath),
               !migrationPlan.items.isEmpty {
                pendingSave.migrationPlan = migrationPlan
                self.pendingSave = pendingSave
                isShowingPodcastMigrationConfirmation = true
                return
            }

            continueSavingWithoutMigration(pendingSave)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func continueSavingWithoutMigration(_ pendingSave: PendingSave) {
        do {
            if try shouldConfirmPodcastDirectoryCreation(pendingSave.podcastDirectoryPath) {
                folderPendingCreation = .podcast
                self.pendingSave = pendingSave
                isShowingCreateFolderConfirmation = true
                return
            }
            if try shouldConfirmPlaylistDirectoryCreation(pendingSave.playlistDirectoryPath) {
                folderPendingCreation = .playlist
                self.pendingSave = pendingSave
                isShowingCreateFolderConfirmation = true
                return
            }

            performSave(pendingSave)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var cleanupEpisodeLimitSelection: Binding<Int?> {
        Binding(
            get: { draft.settings.deviceCleanupPolicy.maximumEpisodesPerPodcast },
            set: { maximumEpisodesPerPodcast in
                draft.settings.deviceCleanupPolicy = DeviceCleanupPolicy(
                    maximumEpisodesPerPodcast: maximumEpisodesPerPodcast
                )
            }
        )
    }

    private func performSave(_ pendingSave: PendingSave) {
        do {
            try onSave(
                pendingSave.settings,
                pendingSave.podcastDirectoryPath,
                pendingSave.playlistDirectoryPath,
                pendingSave.migrationPlan
            )
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
        panel.title = "Choose FFmpeg"
        panel.prompt = "Choose"
        panel.message = "Select the ffmpeg executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let currentURL = draft.ffmpegExecutablePath.isEmpty ? URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true) : URL(fileURLWithPath: draft.ffmpegExecutablePath).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: currentURL.path) {
            panel.directoryURL = currentURL
        }

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        draft.ffmpegExecutablePath = selectedURL.path
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
            draft.podcastDirectoryPath = try Self.relativeDevicePath(
                for: selectedURL,
                rootURL: selectedDeviceRootURL,
                normalizer: DevicePodcastConfiguration.normalizedRelativeDirectoryPath
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func choosePlaylistDirectory() {
        guard let selectedDeviceRootURL else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Playlist Folder"
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
            let relativePath = try Self.relativeDevicePath(
                for: selectedURL,
                rootURL: selectedDeviceRootURL,
                normalizer: DevicePodcastConfiguration.normalizedPlaylistDirectoryPath
            )
            draft.playlistDirectoryPath = relativePath
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func relativeDevicePath(
        for selectedURL: URL,
        rootURL: URL,
        normalizer: (String) throws -> String
    ) throws -> String {
        let rootURL = rootURL.standardizedFileURL
        let selectedURL = selectedURL.standardizedFileURL
        let rootPath = rootURL.path
        let selectedPath = selectedURL.path

        guard selectedPath.hasPrefix(rootPath + "/") else {
            return try normalizer(selectedPath)
        }

        let relativePath = String(selectedPath.dropFirst(rootPath.count + 1))
        return try normalizer(relativePath)
    }

}

private enum DeviceFolderKind {
    case podcast
    case playlist
}

private struct PodcastDirectoryMigrationReviewView: View {
    let plan: DevicePodcastDirectoryMigrationPlan
    let onCancel: () -> Void
    let onLeaveFiles: () -> Void
    let onMoveFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move Existing Podcasts?")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "These \(plan.items.count) app-managed podcast file\(plan.items.count == 1 ? "" : "s") are in \"\(sourceFolderName)\". Move them to \"\(destinationFolderName)\"?"
            )

            List(relativePaths, id: \.self) { path in
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 220)

            Text("Files that are not managed by Simple Podcast Manager will stay where they are.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Leave Files Where They Are", action: onLeaveFiles)
                Button("Move Files", action: onMoveFiles)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 420)
    }

    private var sourceFolderName: String {
        plan.currentDevice.podcastDirectoryURL.lastPathComponent
    }

    private var destinationFolderName: String {
        plan.updatedDevice.podcastDirectoryURL.lastPathComponent
    }

    private var relativePaths: [String] {
        plan.items.map { item in
            let directoryPath = plan.currentDevice.podcastDirectoryURL.standardizedFileURL.path
            let filePath = item.sourceURL.standardizedFileURL.path
            guard filePath.hasPrefix(directoryPath + "/") else {
                return item.sourceURL.lastPathComponent
            }
            return String(filePath.dropFirst(directoryPath.count + 1))
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Divider()
            }

            VStack(alignment: .leading, spacing: 18) {
                content
            }
        }
    }
}

/// Settings keep a consistent rhythm between labels and controls.
private struct SettingsField<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .fontWeight(.semibold)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
    }
}
