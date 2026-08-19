import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct RSSFeedParserTests {
    @Test
    func parsesRSSAfterLongXMLPreamble() throws {
        let preamble = """
        <?xml version="1.0" encoding="utf-8"?>
        <?xml-stylesheet type="text/xsl" media="screen" href="https://example.com/podcast.xsl?theme=default"?>
        """
        #expect(preamble.utf8.count > 128)

        let data = Data("""
        \(preamble)
        <rss version="2.0">
          <channel>
            <title>Hörsaal</title>
            <item>
              <title>Große Fragen</title>
              <guid>episode-1</guid>
              <enclosure url="https://cdn.example.com/episode-1.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """.utf8)

        let parsedFeed = try RSSFeedParser().parse(
            data: data,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!,
            subscriptionID: UUID()
        )

        #expect(parsedFeed.title == "Hörsaal")
        #expect(parsedFeed.episodes.map(\.title) == ["Große Fragen"])
    }
}
