import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastPlaylistEpisodeActionsTests {
    @Test(arguments: [false, true])
    func playlistRowsReuseMembershipMenuAndOnlyAutomaticRowsOfferPin(isAutomatic: Bool) throws {
        let episode = Episode(id: "offline", subscriptionID: UUID(), podcastTitle: "History Podcast",
            title: "Episode", enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/rss")!)
        let entry = try #require(PodcastPlaylistEntry(episode: episode))
        let source = try PodcastPlaylist(name: "History", entries: isAutomatic ? [] : [entry],
            automaticRule: isAutomatic ? PodcastPlaylistAutomaticRule(source: .selectedPodcasts([entry.id.subscriptionID])) : nil)
        let destination = try PodcastPlaylist(name: "Commuting")
        var toggledPlaylistIDs: [PodcastPlaylist.ID] = []
        var pinCount = 0
        let onPin: (() -> Void)? = isAutomatic ? { pinCount += 1 } : nil
        let actions = PodcastPlaylistEpisodeActions(
            episode: episode,
            playlists: [source, destination],
            automaticPlaylistIDs: isAutomatic ? [source.id] : [],
            onTogglePlaylist: { toggledPlaylistIDs.append($0.id) },
            onPin: onPin
        )

        let menu = actions.playlistMenu
        #expect(menu.episode == episode)
        #expect(menu.playlists == [source, destination])
        let indicator = EpisodePlaylistIndicatorPresentation(episode: menu.episode, playlists: menu.playlists,
            automaticPlaylistIDs: menu.automaticPlaylistIDs)
        #expect(indicator.membership(for: source.id) == (isAutomatic ? .automatic : .manual))
        #expect(indicator.membership(for: destination.id) == .none)
        #expect(indicator.isIncluded)

        menu.onTogglePlaylist(destination)
        #expect(toggledPlaylistIDs == [destination.id])
        #expect(pinCount == 0)

        if isAutomatic {
            let pin = try #require(actions.pinButton)
            #expect(!pin.isDisabled)
            #expect(pin.helpText == "Pin as manually added")
            #expect(!pin.isDestructive)
            pin.action()
            #expect(pinCount == 1)
            #expect(toggledPlaylistIDs == [destination.id])
        } else {
            #expect(actions.pinButton == nil)
        }
    }
}
