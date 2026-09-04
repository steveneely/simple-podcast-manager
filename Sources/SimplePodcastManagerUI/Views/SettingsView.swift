import AppKit
import SwiftUI
import SimplePodcastManagerCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
    @State private var appearancePreference: AppearancePreference
    @State private var allowsInsecureDownloads: Bool
    @State private var prefixesPublicationDateInEpisodeTitles: Bool
    @State private var mp3Genre: String
    @State private var automaticDownloadLimit: AutomaticDownloadLimit
    @State private var deviceCleanupPolicy: DeviceCleanupPolicy
    @State private var inactivePodcastThreshold: InactivePodcastThreshold
    @State private var podcastDirectoryPath: String
    @State private var automaticallyChecksForUpdates: Bool
    @State private var errorMessage: String?
    @State private var isShowingCreateFolderConfirmation = false
    @State private var isShowingPodcastMigrationConfirmation = false
    @State private var pendingSave: PendingSave?
    @State private var hasSettledAppearancePreference = false
    private let selectedDeviceName: String?
    private let selectedDeviceRootURL: URL?
    private let savedAppearancePreference: AppearancePreference
    private let showSortOrder: ShowSortOrder
    private let shouldConfirmPodcastDirectoryCreation: (String?) throws -> Bool
    private let makePodcastDirectoryMigrationPlan: (String?) throws -> DevicePodcastDirectoryMigrationPlan?
    private let onSave: (AppSettings, String?, DevicePodcastDirectoryMigrationPlan?) throws -> Void
    private let onAppearancePreferencePreview: (AppearancePreference) -> Void
    private let onAutomaticallyChecksForUpdatesChange: (Bool) -> Void
    private let onBackUpAppData: () -> Void
    private let onRestoreAppData: () -> Void
    private let showsUpdateSettings: Bool

    private struct PendingSave {
        var settings: AppSettings
        var podcastDirectoryPath: String?
        var automaticallyChecksForUpdates: Bool
        var migrationPlan: DevicePodcastDirectoryMigrationPlan?
    }

    public init(
        settings: AppSettings,
        selectedDeviceName: String? = nil,
        selectedDeviceRootURL: URL? = nil,
        podcastDirectoryPath: String? = nil,
        automaticallyChecksForUpdates: Bool? = nil,
        shouldConfirmPodcastDirectoryCreation: @escaping (String?) throws -> Bool = { _ in false },
        makePodcastDirectoryMigrationPlan: @escaping (String?) throws -> DevicePodcastDirectoryMigrationPlan? = { _ in nil },
        onSave: @escaping (AppSettings, String?, DevicePodcastDirectoryMigrationPlan?) throws -> Void,
        onAppearancePreferencePreview: @escaping (AppearancePreference) -> Void = { _ in },
        onAutomaticallyChecksForUpdatesChange: @escaping (Bool) -> Void = { _ in },
        onBackUpAppData: @escaping () -> Void = {},
        onRestoreAppData: @escaping () -> Void = {}
    ) {
        self._ffmpegExecutablePath = State(initialValue: settings.ffmpegExecutablePath ?? "")
        self._appearancePreference = State(initialValue: settings.appearancePreference)
        self._allowsInsecureDownloads = State(initialValue: settings.allowsInsecureDownloads)
        self._prefixesPublicationDateInEpisodeTitles = State(
            initialValue: settings.prefixesPublicationDateInEpisodeTitles
        )
        self._mp3Genre = State(initialValue: settings.mp3Genre)
        self._automaticDownloadLimit = State(initialValue: settings.automaticDownloadLimit)
        self._deviceCleanupPolicy = State(initialValue: settings.deviceCleanupPolicy)
        self._inactivePodcastThreshold = State(initialValue: settings.inactivePodcastThreshold)
        self._podcastDirectoryPath = State(initialValue: podcastDirectoryPath ?? DevicePodcastConfiguration.defaultPodcastDirectoryPath)
        self._automaticallyChecksForUpdates = State(initialValue: automaticallyChecksForUpdates ?? false)
        self._errorMessage = State(initialValue: nil)
        self.selectedDeviceName = selectedDeviceName
        self.selectedDeviceRootURL = selectedDeviceRootURL
        self.savedAppearancePreference = settings.appearancePreference
        self.showSortOrder = settings.showSortOrder
        self.shouldConfirmPodcastDirectoryCreation = shouldConfirmPodcastDirectoryCreation
        self.makePodcastDirectoryMigrationPlan = makePodcastDirectoryMigrationPlan
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection(title: "Episodes") {
                        LabeledField(
                            title: "Automatic Downloads",
                            detail: "Downloads new episodes automatically after feeds refresh. The selected limit applies separately to each included show.",
                            emphasizesTitle: true
                        ) {
                            Picker("Automatic Downloads", selection: $automaticDownloadLimit) {
                                Text("Off").tag(AutomaticDownloadLimit.off)
                                Text("Latest 1").tag(AutomaticDownloadLimit.latest1)
                                Text("Latest 2").tag(AutomaticDownloadLimit.latest2)
                                Text("Latest 3").tag(AutomaticDownloadLimit.latest3)
                                Text("All new").tag(AutomaticDownloadLimit.allNew)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        LabeledField(
                            title: "MP3 Episode Titles",
                            detail: "Adds the date in MM.dd format, such as 08.11 Original Title. Applies to new downloads only.",
                            emphasizesTitle: true
                        ) {
                            Toggle(
                                "Prefix with publication date",
                                isOn: $prefixesPublicationDateInEpisodeTitles
                            )
                            .toggleStyle(.checkbox)
                        }

                        LabeledField(
                            title: "MP3 Genre",
                            detail: "Writes this value to the MP3’s ID3 genre field. Leave blank to omit it. Applies to new downloads only.",
                            emphasizesTitle: true
                        ) {
                            TextField("", text: $mp3Genre)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .accessibilityLabel("MP3 Genre")
                        }

                        LabeledField(
                            title: "Inactive Shows",
                            detail: "Shows an orange Inactive label beside podcasts that have not published recently.",
                            emphasizesTitle: true
                        ) {
                            Picker("Inactive Shows", selection: $inactivePodcastThreshold) {
                                Text("Off").tag(InactivePodcastThreshold.off)
                                Text("After 3 months").tag(InactivePodcastThreshold.threeMonths)
                                Text("After 6 months").tag(InactivePodcastThreshold.sixMonths)
                                Text("After 1 year").tag(InactivePodcastThreshold.oneYear)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    SettingsSection(title: "MP3 Player") {
                        LabeledField(
                            title: "Device Cleanup",
                            detail: "Suggests deleting episodes beyond the selected number per show. You can review and keep any episode before syncing.",
                            emphasizesTitle: true
                        ) {
                            Picker("Device Cleanup", selection: cleanupEpisodeLimitSelection) {
                                Text("Off").tag(Int?.none)
                                ForEach(DeviceCleanupPolicy.allowedMaximumEpisodesPerShow, id: \.self) { count in
                                    Text("Keep \(count) episodes").tag(Int?.some(count))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        LabeledField(
                            title: "Device Podcast Folder",
                            detail: selectedDeviceName.map { "Choose where podcasts are saved on \($0). Defaults to \"music\"." }
                                ?? "Connect a device to choose where its podcasts are saved. Defaults to \"music\".",
                            emphasizesTitle: true
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
                    }

                    SettingsSection(title: "General") {
                        LabeledField(
                            title: "Appearance",
                            detail: "Choose whether the app follows macOS, always uses light mode, or always uses dark mode.",
                            emphasizesTitle: true
                        ) {
                            Picker("Appearance", selection: $appearancePreference) {
                                Text("System").tag(AppearancePreference.system)
                                Text("Light").tag(AppearancePreference.light)
                                Text("Dark").tag(AppearancePreference.dark)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        if showsUpdateSettings {
                            LabeledField(title: "Updates", emphasizesTitle: true) {
                                Toggle(
                                    "Check for updates on startup",
                                    isOn: $automaticallyChecksForUpdates
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    SettingsSection(title: "Advanced") {
                        LabeledField(
                            title: "ffmpeg Path",
                            detail: "Optional. Needed only to convert non-MP3 podcast audio.",
                            emphasizesTitle: true
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
                            detail: "HTTPS is always tried first. HTTP audio and artwork are unencrypted and could be intercepted or changed in transit.",
                            emphasizesTitle: true
                        ) {
                            Toggle(
                                "Always allow HTTP podcast downloads",
                                isOn: $allowsInsecureDownloads
                            )
                            .toggleStyle(.checkbox)
                        }
                    }

                    SettingsSection(title: "App Data") {
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 520, height: 600)
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
                allowsInsecureDownloads: allowsInsecureDownloads,
                prefixesPublicationDateInEpisodeTitles: prefixesPublicationDateInEpisodeTitles,
                mp3Genre: normalizedMP3Genre,
                automaticDownloadLimit: automaticDownloadLimit,
                deviceCleanupPolicy: deviceCleanupPolicy,
                inactivePodcastThreshold: inactivePodcastThreshold,
                showSortOrder: showSortOrder
            ),
            podcastDirectoryPath: selectedDeviceName == nil ? nil : podcastDirectoryPath,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
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
                self.pendingSave = pendingSave
                isShowingCreateFolderConfirmation = true
                return
            }

            performSave(pendingSave)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var normalizedMP3Genre: String {
        mp3Genre.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanupEpisodeLimitSelection: Binding<Int?> {
        Binding(
            get: { deviceCleanupPolicy.maximumEpisodesPerShow },
            set: { maximumEpisodesPerShow in
                deviceCleanupPolicy = DeviceCleanupPolicy(
                    maximumEpisodesPerShow: maximumEpisodesPerShow
                )
            }
        )
    }

    private func performSave(_ pendingSave: PendingSave) {
        do {
            try onSave(
                pendingSave.settings,
                pendingSave.podcastDirectoryPath,
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

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
    }
}
