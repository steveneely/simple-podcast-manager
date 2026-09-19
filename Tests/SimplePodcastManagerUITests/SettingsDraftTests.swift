import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct SettingsDraftTests {
    @Test
    func openingAndNavigatingSettingsDoesNotEnableSave() {
        var draft = SettingsDraft(settings: AppSettings())
        for page in SettingsPage.allCases {
            draft.selectedPage = page
            #expect(!draft.hasChanges)
        }
    }

    @Test
    func revertingPreferenceEditsDisablesSaveAgain() {
        let original = AppSettings(appearancePreference: .system, mp3Genre: "Podcast")
        var draft = SettingsDraft(settings: original)
        draft.settings.appearancePreference = .dark
        #expect(draft.hasChanges)
        draft.selectedPage = .advanced
        #expect(draft.hasChanges)
        draft.settings.appearancePreference = .system
        #expect(!draft.hasChanges)
        draft.settings.mp3Genre = "Speech"
        #expect(draft.hasChanges)
        draft.settings.mp3Genre = "Podcast"
        #expect(!draft.hasChanges)
    }

    @Test
    func changesCompareTheValuesThatWillActuallyBeSaved() {
        var draft = SettingsDraft(settings: AppSettings(ffmpegExecutablePath: "/tools/ffmpeg", mp3Genre: "Podcast"))
        draft.ffmpegExecutablePath = " /tools/ffmpeg \n"
        draft.settings.mp3Genre = " Podcast \n"
        #expect(!draft.hasChanges)
        draft.ffmpegExecutablePath = ""
        #expect(draft.hasChanges)
        draft.ffmpegExecutablePath = "/tools/ffmpeg"
        #expect(!draft.hasChanges)
        let legacyWhitespace = SettingsDraft(settings: AppSettings(ffmpegExecutablePath: " ", mp3Genre: " Podcast "))
        #expect(!legacyWhitespace.hasChanges)
    }

    @Test
    func deviceFolderEditsIndependentlyEnableSaveAndCanBeReverted() {
        var draft = SettingsDraft(settings: AppSettings(), podcastDirectoryPath: "audio", playlistDirectoryPath: "lists")
        #expect(!draft.hasChanges)
        draft.podcastDirectoryPath = "podcasts"
        #expect(draft.hasChanges)
        draft.podcastDirectoryPath = "audio"
        #expect(!draft.hasChanges)
        draft.playlistDirectoryPath = "playlists"
        #expect(draft.hasChanges)
        draft.playlistDirectoryPath = "lists"
        #expect(!draft.hasChanges)
        let defaults = SettingsDraft(settings: AppSettings(), podcastDirectoryPath: "audio")
        #expect(defaults.playlistDirectoryPath == "audio")
        #expect(!defaults.hasChanges)
    }

    @Test
    func updatePreferenceEditsEnableSaveOnlyWhenUpdatesAreAvailable() {
        var draft = SettingsDraft(settings: AppSettings(), automaticallyChecksForUpdates: false)
        #expect(!draft.hasChanges)
        draft.automaticallyChecksForUpdates = true
        #expect(draft.hasChanges)
        draft.automaticallyChecksForUpdates = false
        #expect(!draft.hasChanges)
        var unavailable = SettingsDraft(settings: AppSettings())
        unavailable.automaticallyChecksForUpdates = true
        #expect(!unavailable.hasChanges)
    }

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
