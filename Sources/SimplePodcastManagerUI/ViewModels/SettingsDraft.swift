import Foundation
import SimplePodcastManagerCore

/// One unsaved draft shared by every Settings page.
struct SettingsDraft {
    var settings: AppSettings
    var ffmpegExecutablePath: String
    var podcastDirectoryPath: String
    var playlistDirectoryPath: String
    var automaticallyChecksForUpdates: Bool
    var selectedPage: SettingsPage = .general

    private let savedSettings: AppSettings
    private let savedPodcastDirectoryPath: String
    private let savedPlaylistDirectoryPath: String
    private let savedAutomaticallyChecksForUpdates: Bool?

    init(
        settings: AppSettings,
        podcastDirectoryPath: String? = nil,
        playlistDirectoryPath: String? = nil,
        automaticallyChecksForUpdates: Bool? = nil
    ) {
        self.settings = settings
        self.ffmpegExecutablePath = settings.ffmpegExecutablePath ?? ""
        let podcastPath = podcastDirectoryPath ?? DevicePodcastConfiguration.defaultPodcastDirectoryPath
        let playlistPath = playlistDirectoryPath ?? podcastPath
        self.podcastDirectoryPath = podcastPath
        self.playlistDirectoryPath = playlistPath
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates ?? false
        self.savedSettings = Self.normalizedSettings(settings, ffmpegExecutablePath: settings.ffmpegExecutablePath ?? "")
        self.savedPodcastDirectoryPath = podcastPath
        self.savedPlaylistDirectoryPath = playlistPath
        self.savedAutomaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    var hasChanges: Bool {
        settingsForSaving != savedSettings
            || podcastDirectoryPath != savedPodcastDirectoryPath
            || playlistDirectoryPath != savedPlaylistDirectoryPath
            || savedAutomaticallyChecksForUpdates.map { $0 != automaticallyChecksForUpdates } == true
    }

    var settingsForSaving: AppSettings {
        Self.normalizedSettings(settings, ffmpegExecutablePath: ffmpegExecutablePath)
    }

    private static func normalizedSettings(_ settings: AppSettings, ffmpegExecutablePath: String) -> AppSettings {
        var saved = settings
        let path = ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.ffmpegExecutablePath = path.isEmpty ? nil : path
        saved.mp3Genre = settings.mp3Genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case downloads = "Downloads"
    case device = "Device"
    case advanced = "Advanced"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .downloads: "arrow.down.circle"
        case .device: "externaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }
}
