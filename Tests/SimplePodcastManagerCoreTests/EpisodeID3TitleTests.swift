import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct EpisodeID3TitleTests {
    @Test
    func prefixesPublicationDateInMonthDayFormatWhenEnabled() throws {
        let publicationDate = try #require(ISO8601DateFormatter().date(from: "2026-08-11T12:00:00Z"))
        let episode = makeEpisode(
            title: "Original Title",
            publicationDate: publicationDate
        )

        #expect(EpisodeID3Title.title(for: episode, prefixesPublicationDate: true) == "08.11 Original Title")
    }

    @Test
    func preservesOriginalTitleWhenPrefixIsDisabled() {
        let episode = makeEpisode(
            title: "Original Title",
            publicationDate: Date(timeIntervalSince1970: 1_786_406_400)
        )

        #expect(EpisodeID3Title.title(for: episode, prefixesPublicationDate: false) == "Original Title")
    }

    @Test
    func preservesOriginalTitleWhenPublicationDateIsMissing() {
        let episode = makeEpisode(title: "Original Title", publicationDate: nil)

        #expect(EpisodeID3Title.title(for: episode, prefixesPublicationDate: true) == "Original Title")
    }

    @Test
    func usesUTCForDatesNearDayBoundary() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-11T00:30:00Z"))
        let episode = makeEpisode(title: "Boundary Episode", publicationDate: date)

        #expect(EpisodeID3Title.title(for: episode, prefixesPublicationDate: true) == "08.11 Boundary Episode")
    }

    private func makeEpisode(title: String, publicationDate: Date?) -> Episode {
        Episode(
            id: "episode",
            podcastTitle: "Example Podcast",
            title: title,
            publicationDate: publicationDate,
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
    }
}
