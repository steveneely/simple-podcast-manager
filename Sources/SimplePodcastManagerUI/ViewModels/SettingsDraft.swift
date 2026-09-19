import Foundation
import SimplePodcastManagerCore

/// One unsaved draft shared by every Settings page.
struct SettingsDraft {
    var settings: AppSettings
    var ffmpegExecutablePath: String
    var selectedPage: SettingsPage = .general

    init(settings: AppSettings) {
        self.settings = settings
        self.ffmpegExecutablePath = settings.ffmpegExecutablePath ?? ""
    }

    var settingsForSaving: AppSettings {
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
