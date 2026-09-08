import Testing
@testable import SimplePodcastManagerCore

struct PodcastPlaylistNameTests {
    @Test(arguments: ["", ".hidden", "Trailing.", "CON", "COM1", "Bad/Name"])
    func rejectsNamesThatAreUnsafeOrUnclearOnFAT(_ name: String) {
        #expect(throws: PodcastPlaylistError.self) {
            try PodcastPlaylistName.validated(name)
        }
    }

    @Test
    func acceptsUnicodeAndCreatesM3UFileName() throws {
        let name = try PodcastPlaylistName.validated("Hörenswert")

        #expect(PodcastPlaylistName.deviceFileName(for: name) == "Hörenswert.m3u")
    }
}
