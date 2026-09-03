import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct FeedURLIdentityTests {
    @Test
    func normalizesCommonWebFeedAliases() throws {
        let httpsURL = try #require(URL(string: "https://Feeds.Example.com:443/show/feed.xml/"))
        let httpURL = try #require(URL(string: "http://feeds.example.com/show/feed.xml#episodes"))

        #expect(FeedURLIdentity.normalized(httpsURL) == FeedURLIdentity.normalized(httpURL))
    }

    @Test
    func preservesPathCaseAndQueryParameters() throws {
        let firstURL = try #require(URL(string: "https://feeds.example.com/Show.xml?member=one"))
        let secondURL = try #require(URL(string: "https://feeds.example.com/show.xml?member=two"))

        #expect(FeedURLIdentity.normalized(firstURL) != FeedURLIdentity.normalized(secondURL))
    }
}
