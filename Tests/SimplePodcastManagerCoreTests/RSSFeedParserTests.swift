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

    @Test
    func usesFirstNonemptyEpisodeDescriptionSource() throws {
        let data = Data("""
        <rss version="2.0"
             xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Example Podcast</title>
            <item>
              <title>Preferred Description</title>
              <content:encoded><![CDATA[<p>Preferred content.</p>]]></content:encoded>
              <itunes:summary>Unused summary.</itunes:summary>
              <description>Unused description.</description>
              <enclosure url="https://cdn.example.com/preferred.mp3" type="audio/mpeg"/>
            </item>
            <item>
              <title>Fallback Description</title>
              <content:encoded><![CDATA[<p> </p>]]></content:encoded>
              <itunes:summary>Fallback summary.</itunes:summary>
              <description>Unused description.</description>
              <enclosure url="https://cdn.example.com/fallback.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """.utf8)

        let parsedFeed = try RSSFeedParser().parse(
            data: data,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!,
            subscriptionID: UUID()
        )

        #expect(parsedFeed.episodes.map(\.description) == ["Preferred content.", "Fallback summary."])
    }
}
