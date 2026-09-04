import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct EpisodeFileNameTests {
    @Test
    func directoryNameUsesMP3PlayerFriendlyASCII() {
        let subscription = PodcastSubscription(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "\u{201C}The Cognitive Revolution\u{201D} | AI Builders, Researchers, and Live Player Analysis",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )

        #expect(EpisodeFileName.directoryName(for: subscription) == "The Cognitive Revolution-AI Builders, Researchers, and Live Player Analysis")
    }

    @Test
    func fileNameUsesPrintableASCIIOnly() {
        let episode = Episode(
            id: "ep-1",
            podcastTitle: "\u{201C}The Cognitive Revolution\u{201D}",
            title: "\u{201C}Gemini\u{201D}\u{2014}Google\u{2019}s AI launch\u{2026}",
            publicationDate: Date(timeIntervalSince1970: 1_779_235_200),
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        let fileName = EpisodeFileName.fileName(for: episode, fileExtension: "mp3")

        #expect(fileName == "2026.05.20-Gemini-Google's AI launch...-(The Cognitive Revolution).mp3")
        #expect(fileName.unicodeScalars.allSatisfy { (32...126).contains($0.value) })
    }

    @Test
    func fileNameTransliteratesSpecialLatinCharactersReadably() {
        let episode = Episode(
            id: "ep-2",
            podcastTitle: "Hörspiel für große Hörer",
            title: "Die größte Æsir-Reise nach Łódź und Øresund",
            enclosureURL: URL(string: "https://example.com/episode.mp3")!,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )

        let fileName = EpisodeFileName.fileName(for: episode, fileExtension: "mp3")

        #expect(fileName == "Die grosste AEsir-Reise nach Lodz und Oresund-(Horspiel fur grosse Horer).mp3")
        #expect(fileName.unicodeScalars.allSatisfy { (32...126).contains($0.value) })
    }

    @Test
    func managedEpisodeMatchingUsesTheSameUnicodeTransliterationAsFileNames() {
        let subscription = PodcastSubscription(
            title: "Hörspiel für große Hörer",
            rssURL: URL(string: "https://example.com/feed.xml")!
        )
        let currentFile = URL(fileURLWithPath: "/music/Horspiel fur grosse Horer/Episode-(Horspiel fur grosse Horer).mp3")

        #expect(EpisodeFileName.isManagedEpisodeFile(currentFile, for: subscription))
    }
}
