import Foundation
import Testing
@testable import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastEpisodeDownloadSelectionTests {
    @Test
    func selectAllCheckboxTracksSelectionAndClearsOnUncheck() {
        var selection = makeSelection()
        let unavailable: Set<String> = ["2", "3"]
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))

        select("1", in: &selection)
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))

        selection.setAllSelected(true, unavailableIDs: unavailable)
        #expect(selection.areAllSelected(unavailableIDs: unavailable))
        #expect(selection.selectedEpisodes(unavailableIDs: unavailable).map(\.id) == ["0", "1", "4", "5"])

        selection.setSelected(false, episodeID: "4", extendingRange: false, unavailableIDs: unavailable)
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))

        selection.setAllSelected(true, unavailableIDs: unavailable)
        selection.setAllSelected(false, unavailableIDs: unavailable)
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))
        #expect(selection.selectedEpisodes(unavailableIDs: unavailable).isEmpty)
    }

    @Test
    func selectAllCheckboxRemainsUncheckedWhenNothingIsAvailable() {
        var selection = makeSelection()
        let unavailable = Set((0..<6).map(String.init))
        selection.setAllSelected(true, unavailableIDs: unavailable)
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))
        #expect(selection.selectedEpisodes(unavailableIDs: unavailable).isEmpty)
        #expect(!makeSelection(count: 0).areAllSelected(unavailableIDs: []))

        selection.setAllSelected(true, unavailableIDs: [])
        #expect(!selection.areAllSelected(unavailableIDs: unavailable))
    }

    @Test
    func startsEmptyAndSelectsOnlyRequestedEpisodesInDisplayOrder() {
        var selection = makeSelection()
        #expect(selection.selectedEpisodes(unavailableIDs: []).isEmpty)

        select("4", in: &selection)
        select("1", in: &selection)
        #expect(selection.selectedEpisodes(unavailableIDs: []).map(\.id) == ["1", "4"])

        selection.setSelected(false, episodeID: "1", extendingRange: false, unavailableIDs: [])
        #expect(selection.selectedEpisodes(unavailableIDs: []).map(\.id) == ["4"])
    }

    @Test(arguments: [false, true])
    func shiftClickSelectsInclusiveRangeInEitherDirection(reverse: Bool) {
        var selection = makeSelection()
        select(reverse ? "4" : "1", in: &selection)
        select(reverse ? "1" : "4", in: &selection, extendingRange: true)
        #expect(selection.selectedEpisodes(unavailableIDs: []).map(\.id) == ["1", "2", "3", "4"])
    }

    @Test
    func rangeSkipsDownloadedAndQueuedEpisodesAndKeepsItsAnchor() {
        var selection = makeSelection()
        let unavailable: Set<String> = ["2", "3"]
        select("1", in: &selection, unavailableIDs: unavailable)
        select("4", in: &selection, extendingRange: true, unavailableIDs: unavailable)
        select("5", in: &selection, extendingRange: true, unavailableIDs: unavailable)
        #expect(selection.selectedEpisodes(unavailableIDs: unavailable).map(\.id) == ["1", "4", "5"])
    }

    @Test
    func shiftClickCanDeselectARange() {
        var selection = makeSelection()
        selection.selectAll(unavailableIDs: [])
        selection.setSelected(false, episodeID: "1", extendingRange: false, unavailableIDs: [])
        selection.setSelected(false, episodeID: "4", extendingRange: true, unavailableIDs: [])
        #expect(selection.selectedEpisodes(unavailableIDs: []).map(\.id) == ["0", "5"])
    }

    @Test
    func selectAllIncludesWholeBacklogAndExcludesUnavailableEpisodes() {
        var selection = makeSelection(count: 2_000)
        let unavailable: Set<String> = ["0", "1000", "1999"]
        selection.selectAll(unavailableIDs: unavailable)
        let episodes = selection.selectedEpisodes(unavailableIDs: unavailable)
        #expect(episodes.count == 1_997)
        #expect(episodes.first?.id == "1")
        #expect(episodes.last?.id == "1998")
        #expect(Set(episodes.map(\.id)).isDisjoint(with: unavailable))
    }

    @Test
    func confirmationExcludesEpisodesThatBecomeUnavailableWhileSelecting() {
        var selection = makeSelection()
        selection.selectAll(unavailableIDs: [])
        #expect(selection.selectedEpisodes(unavailableIDs: ["1", "4"]).map(\.id) == ["0", "2", "3", "5"])
        #expect(selection.selectedEpisodes(unavailableIDs: Set((0..<6).map(String.init))).isEmpty)
    }

    @Test
    func deselectAllClearsTheRangeAnchor() {
        var selection = makeSelection()
        select("1", in: &selection)
        selection.deselectAll()
        #expect(selection.selectedEpisodes(unavailableIDs: []).isEmpty)
        select("4", in: &selection, extendingRange: true)
        #expect(selection.selectedEpisodes(unavailableIDs: []).map(\.id) == ["4"])
    }

    @Test
    func unavailableAndUnknownEpisodesCannotBeSelected() {
        var selection = makeSelection()
        select("missing", in: &selection)
        select("1", in: &selection, unavailableIDs: ["1"])
        #expect(selection.selectedIDs.isEmpty)

        var empty = makeSelection(count: 0)
        empty.selectAll(unavailableIDs: [])
        select("0", in: &empty, extendingRange: true)
        #expect(empty.selectedEpisodes(unavailableIDs: []).isEmpty)
    }

    private func select(
        _ id: String,
        in selection: inout PodcastEpisodeDownloadSelection,
        extendingRange: Bool = false,
        unavailableIDs: Set<String> = []
    ) {
        selection.setSelected(true, episodeID: id, extendingRange: extendingRange, unavailableIDs: unavailableIDs)
    }

    private func makeSelection(count: Int = 6) -> PodcastEpisodeDownloadSelection {
        let podcastID = UUID()
        let episodes = (0..<count).map { index in
            Episode(
                id: String(index),
                subscriptionID: podcastID,
                podcastTitle: "Narrative Podcast",
                title: "Episode \(index)",
                enclosureURL: URL(string: "https://example.com/\(index).mp3")!,
                sourceFeedURL: URL(string: "https://example.com/rss")!
            )
        }
        return PodcastEpisodeDownloadSelection(episodes: episodes)
    }
}
