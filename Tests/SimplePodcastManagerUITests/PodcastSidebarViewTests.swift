import Foundation
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct PodcastSidebarViewTests {
    @Test
    func appStartsWithoutSelectingAPodcast() {
        #expect(PodcastSelectionPolicy.initialSelection == nil)
    }

    @Test
    func clickingSelectedPodcastClearsSelection() {
        let subscriptionID = UUID()

        let selection = PodcastSidebarView.selection(
            afterClicking: subscriptionID,
            currentSelection: subscriptionID
        )

        #expect(selection == nil)
    }

    @Test
    func clickingDifferentPodcastSelectsIt() {
        let selectedID = UUID()
        let clickedID = UUID()

        let selection = PodcastSidebarView.selection(
            afterClicking: clickedID,
            currentSelection: selectedID
        )

        #expect(selection == clickedID)
    }

    @Test
    func newEpisodeStatusTakesPrecedenceOverInactiveStatus() {
        let status = PodcastSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: true,
            hasPodcastIssue: false,
            isEnabled: true
        )

        #expect(status == .newEpisodes(4))
    }

    @Test
    func refreshIssueAndDisabledPodcastHideActivityStatus() {
        #expect(PodcastSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: false,
            hasPodcastIssue: true,
            isEnabled: true
        ) == nil)
        #expect(PodcastSidebarView.activityStatus(
            newEpisodeCount: 4,
            isInactive: false,
            hasPodcastIssue: false,
            isEnabled: false
        ) == nil)
    }

    @Test
    func inactiveStatusAppearsWithoutNewEpisodes() {
        let status = PodcastSidebarView.activityStatus(
            newEpisodeCount: 0,
            isInactive: true,
            hasPodcastIssue: false,
            isEnabled: true
        )

        #expect(status == .inactive)
    }

    @Test
    func newEpisodeLabelCapsLargeCounts() {
        #expect(PodcastSidebarView.newEpisodeLabel(for: 4) == "4 new")
        #expect(PodcastSidebarView.newEpisodeLabel(for: 100) == "99+ new")
    }

    @Test
    func alphabeticSortOrdersPodcastsByTitle() {
        let bravo = makeSubscription(title: "Bravo")
        let alpha = makeSubscription(title: "alpha")

        let sorted = PodcastSidebarView.sortedSubscriptions(
            [bravo, alpha],
            by: .alphabetic,
            newestPublicationDate: { _ in nil }
        )

        #expect(sorted.map(\.id) == [alpha.id, bravo.id])
    }

    @Test
    func reverseAlphabeticSortOrdersPodcastsFromZToA() {
        let bravo = makeSubscription(title: "Bravo")
        let alpha = makeSubscription(title: "Alpha")

        let sorted = PodcastSidebarView.sortedSubscriptions(
            [alpha, bravo],
            by: .reverseAlphabetic,
            newestPublicationDate: { _ in nil }
        )

        #expect(sorted.map(\.id) == [bravo.id, alpha.id])
    }

    @Test
    func recentlyUpdatedSortUsesNewestEpisodeThenTitleAndPlacesUndatedPodcastsLast() {
        let older = makeSubscription(title: "Older")
        let newestZulu = makeSubscription(title: "Zulu")
        let newestAlpha = makeSubscription(title: "Alpha")
        let undated = makeSubscription(title: "Undated")
        let dates = [
            older.id: Date(timeIntervalSince1970: 100),
            newestZulu.id: Date(timeIntervalSince1970: 200),
            newestAlpha.id: Date(timeIntervalSince1970: 200),
        ]

        let sorted = PodcastSidebarView.sortedSubscriptions(
            [undated, newestZulu, older, newestAlpha],
            by: .recentlyUpdated,
            newestPublicationDate: { dates[$0.id] }
        )

        #expect(sorted.map(\.id) == [newestAlpha.id, newestZulu.id, older.id, undated.id])
    }

    @Test
    func leastRecentlyUpdatedSortPlacesUndatedAndOldestPodcastsFirst() {
        let older = makeSubscription(title: "Older")
        let newer = makeSubscription(title: "Newer")
        let undatedZulu = makeSubscription(title: "Zulu")
        let undatedAlpha = makeSubscription(title: "Alpha")
        let dates = [
            older.id: Date(timeIntervalSince1970: 100),
            newer.id: Date(timeIntervalSince1970: 200),
        ]

        let sorted = PodcastSidebarView.sortedSubscriptions(
            [newer, undatedZulu, older, undatedAlpha],
            by: .leastRecentlyUpdated,
            newestPublicationDate: { dates[$0.id] }
        )

        #expect(sorted.map(\.id) == [undatedAlpha.id, undatedZulu.id, older.id, newer.id])
    }

    @Test
    func columnHeaderReversesTheCurrentSortDirection() {
        #expect(PodcastSidebarView.reversedSortOrder(.alphabetic) == .reverseAlphabetic)
        #expect(PodcastSidebarView.reversedSortOrder(.reverseAlphabetic) == .alphabetic)
        #expect(PodcastSidebarView.reversedSortOrder(.recentlyUpdated) == .leastRecentlyUpdated)
        #expect(PodcastSidebarView.reversedSortOrder(.leastRecentlyUpdated) == .recentlyUpdated)
    }

    @Test
    func choosingASortCriterionUsesItsNaturalDefaultDirection() {
        #expect(PodcastSidebarView.defaultSortOrder(for: .name) == .alphabetic)
        #expect(PodcastSidebarView.defaultSortOrder(for: .recentlyUpdated) == .recentlyUpdated)
        #expect(PodcastSidebarView.sortCriterion(for: .reverseAlphabetic) == .name)
        #expect(PodcastSidebarView.sortCriterion(for: .leastRecentlyUpdated) == .recentlyUpdated)
    }

    @Test
    func removingSelectedPodcastDoesNotOpenAnotherPodcast() {
        let selectedFeed = makeSubscription(title: "Selected")
        let remainingFeed = makeSubscription(title: "Remaining")

        let selection = PodcastSelectionPolicy.selectionAfterRemovingPodcasts(
            currentSelection: selectedFeed.id,
            remainingSubscriptions: [remainingFeed]
        )

        #expect(selection == nil)
    }

    @Test
    func removingAnotherPodcastKeepsCurrentSelection() {
        let selectedFeed = makeSubscription(title: "Selected")

        let selection = PodcastSelectionPolicy.selectionAfterRemovingPodcasts(
            currentSelection: selectedFeed.id,
            remainingSubscriptions: [selectedFeed]
        )

        #expect(selection == selectedFeed.id)
    }

    private func makeSubscription(title: String) -> PodcastSubscription {
        PodcastSubscription(
            title: title,
            rssURL: URL(string: "https://example.com/\(UUID().uuidString).xml")!
        )
    }
}
