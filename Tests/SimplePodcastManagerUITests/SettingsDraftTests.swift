import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct SettingsDraftTests {
    @Test
    func editsSurvivePageChangesWithoutChangingSavedSettings() {
        let original = AppSettings()
        var draft = SettingsDraft(settings: original)
        #expect(draft.selectedPage == .general)
        draft.settings.appearancePreference = .dark
        draft.selectedPage = .downloads
        draft.settings.automaticDownloadLimit = .latest3
        draft.settings.mp3Genre = "  Spoken Word \n"
        draft.selectedPage = .advanced
        draft.settings.allowsInsecureDownloads = true
        draft.ffmpegExecutablePath = " /opt/homebrew/bin/ffmpeg \n"
        draft.selectedPage = .device
        draft.settings.deviceCleanupPolicy = DeviceCleanupPolicy(maximumEpisodesPerPodcast: 5)
        draft.selectedPage = .advanced
        draft.selectedPage = .downloads

        let saved = draft.settingsForSaving
        #expect(saved.appearancePreference == .dark)
        #expect(saved.automaticDownloadLimit == .latest3)
        #expect(saved.deviceCleanupPolicy.maximumEpisodesPerPodcast == 5)
        #expect(saved.mp3Genre == "Spoken Word")
        #expect(saved.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(saved.allowsInsecureDownloads)
        #expect(draft.settings.mp3Genre == "  Spoken Word \n")
        #expect(original == AppSettings())
    }

    @Test
    func savingPreservesPreferencesOutsideSettingsPages() {
        let original = AppSettings(
            allowsInsecureDownloads: true,
            prefixesPublicationDateInEpisodeTitles: true,
            ejectDeviceAfterSync: false,
            deleteDownloadedEpisodesAfterSync: false,
            podcastSortOrder: .leastRecentlyUpdated
        )
        var draft = SettingsDraft(settings: original)
        draft.settings.inactivePodcastThreshold = .oneYear
        var expected = original
        expected.inactivePodcastThreshold = .oneYear

        #expect(draft.settingsForSaving == expected)
    }

    @Test
    func blankFieldsClearFFmpegAndOmitGenre() {
        var draft = SettingsDraft(settings: AppSettings(ffmpegExecutablePath: "/old/ffmpeg"))
        draft.ffmpegExecutablePath = " \n"
        draft.settings.mp3Genre = " \n"

        #expect(draft.settingsForSaving.ffmpegExecutablePath == nil)
        #expect(draft.settingsForSaving.mp3Genre.isEmpty)
    }

    @Test
    func reopeningFromSavedSettingsDiscardsUnappliedEdits() {
        let original = AppSettings(appearancePreference: .light, mp3Genre: "Speech")
        var draft = SettingsDraft(settings: original)
        draft.settings.appearancePreference = .dark
        draft.settings.mp3Genre = "Changed"
        draft = SettingsDraft(settings: original)

        #expect(draft.settingsForSaving == original)
    }
}
