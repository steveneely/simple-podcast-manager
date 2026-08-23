import AppKit
import SimplePodcastManagerCore

public enum ApplicationAppearance {
    public static func appearance(for preference: AppearancePreference) -> NSAppearance? {
        switch preference {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
