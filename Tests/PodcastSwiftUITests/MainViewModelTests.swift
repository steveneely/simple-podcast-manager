import Foundation
import Testing
@testable import PodcastSwiftCore
@testable import PodcastSwiftUI

@MainActor
struct MainViewModelTests {
    @Test
    func loadReflectsStoredConfiguration() throws {
        let store = InMemoryConfigurationStore(
            configuration: AppConfiguration(
                settings: AppSettings(
                    ffmpegExecutablePath: "/usr/local/bin/ffmpeg",
                    dryRunByDefault: false,
                    ejectAfterSyncByDefault: true
                ),
                feedSubscriptions: [
                    FeedSubscription(title: "ATP", rssURL: URL(string: "https://atp.fm/rss")!)
                ]
            )
        )
        let viewModel = MainViewModel(store: store)

        viewModel.load()

        #expect(viewModel.hasLoadedConfiguration)
        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(viewModel.settings.dryRunByDefault == false)
        #expect(viewModel.settings.ejectAfterSyncByDefault)
    }

    @Test
    func addUpdateAndRemoveFeedPersistThroughStore() throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(store: store)

        viewModel.addFeed(
            from: FeedDraft(
                title: "Connected",
                rssURLString: "https://relay.fm/connected/feed",
                retentionEpisodeLimit: 4
            )
        )

        #expect(viewModel.feedSubscriptions.count == 1)
        #expect(store.configuration.feedSubscriptions.count == 1)

        let existingSubscription = try #require(viewModel.feedSubscriptions.first)
        viewModel.updateFeed(
            from: FeedDraft(
                id: existingSubscription.id,
                title: "Connected (Relay)",
                rssURLString: "https://relay.fm/connected/feed",
                retentionEpisodeLimit: 6,
                isEnabled: false
            )
        )

        #expect(viewModel.feedSubscriptions.first?.title == "Connected (Relay)")
        #expect(viewModel.feedSubscriptions.first?.retentionPolicy.episodeLimit == 6)
        #expect(viewModel.feedSubscriptions.first?.isEnabled == false)

        viewModel.removeFeeds(at: IndexSet(integer: 0))

        #expect(viewModel.feedSubscriptions.isEmpty)
        #expect(store.configuration.feedSubscriptions.isEmpty)
    }

    @Test
    func settingsMutationsPersist() throws {
        let store = InMemoryConfigurationStore()
        let viewModel = MainViewModel(store: store)

        viewModel.setFFmpegExecutablePath("/opt/homebrew/bin/ffmpeg")
        viewModel.setDryRunByDefault(false)
        viewModel.setEjectAfterSyncByDefault(true)

        #expect(viewModel.settings.ffmpegExecutablePath == "/opt/homebrew/bin/ffmpeg")
        #expect(viewModel.settings.dryRunByDefault == false)
        #expect(viewModel.settings.ejectAfterSyncByDefault == true)
        #expect(store.configuration.settings == viewModel.settings)
    }
}

private final class InMemoryConfigurationStore: ConfigurationStore, @unchecked Sendable {
    var configuration: AppConfiguration = AppConfiguration()

    init(configuration: AppConfiguration = AppConfiguration()) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> AppConfiguration {
        configuration
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        self.configuration = configuration
    }
}
