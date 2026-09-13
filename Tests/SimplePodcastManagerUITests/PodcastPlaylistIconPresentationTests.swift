import AppKit
import Testing
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

struct PodcastPlaylistIconPresentationTests {
    @Test
    func everyPlaylistIconUsesADistinctSystemSymbol() {
        let systemImageNames = PodcastPlaylistIcon.allCases.map(\.systemImageName)

        #expect(systemImageNames == [
            "music.note.list",
            "star",
            "newspaper",
            "building.columns",
            "cpu",
            "bicycle",
            "figure.run",
            "tram",
            "house",
            "leaf",
            "moon.zzz",
        ])
        #expect(Set(systemImageNames).count == PodcastPlaylistIcon.allCases.count)
        #expect(systemImageNames.allSatisfy {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        })
    }
}
