import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct OPMLSubscriptionServiceTests {
    private let service = OPMLSubscriptionService()

    @Test
    func importPreviewAddsNewFeedsAndCountsSkippedEntries() throws {
        let data = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <body>
                <outline text="Technology">
                  <outline TITLE="New Podcast" XMLURL="https://example.com/new.xml" type="rss"/>
                  <outline text="Existing Podcast" xmlUrl="https://example.com/existing.xml" type="rss"/>
                  <outline text="Same Feed" xmlUrl="https://example.com/new.xml" type="rss"/>
                  <outline text="Invalid Feed" xmlUrl="ftp://example.com/feed.xml" type="rss"/>
                </outline>
              </body>
            </opml>
            """.utf8
        )

        let preview = try service.importPreview(
            data: data,
            existingSubscriptions: [
                PodcastSubscription(title: "Existing Podcast", rssURL: URL(string: "https://example.com/existing.xml")!)
            ]
        )

        #expect(preview.subscriptionsToAdd == [
            OPMLSubscription(title: "New Podcast", rssURL: URL(string: "https://example.com/new.xml")!)
        ])
        #expect(preview.alreadySubscribedCount == 1)
        #expect(preview.duplicateEntryCount == 1)
        #expect(preview.invalidEntryCount == 1)
    }

    @Test
    func importPreviewRejectsNonOPMLAndEmptySubscriptionLists() {
        #expect(throws: OPMLSubscriptionError.invalidDocument) {
            try service.importPreview(
                data: Data("<rss><channel/></rss>".utf8),
                existingSubscriptions: []
            )
        }

        #expect(throws: OPMLSubscriptionError.noSubscriptions) {
            try service.importPreview(
                data: Data("<opml version=\"2.0\"><body/></opml>".utf8),
                existingSubscriptions: []
            )
        }
    }

    @Test
    func exportedSubscriptionsCanBeImportedWithoutLosingEscapedTitles() throws {
        let sourceSubscriptions = [
            PodcastSubscription(title: "Zebra", rssURL: URL(string: "https://example.com/zebra.xml")!),
            PodcastSubscription(title: "Alpha & \"Beta\"", rssURL: URL(string: "https://example.com/alpha.xml?source=one&format=rss")!),
        ]

        let exportedData = service.exportSubscriptions(sourceSubscriptions)
        let preview = try service.importPreview(data: exportedData, existingSubscriptions: [])

        #expect(preview.subscriptionsToAdd == [
            OPMLSubscription(
                title: "Alpha & \"Beta\"",
                rssURL: URL(string: "https://example.com/alpha.xml?source=one&format=rss")!
            ),
            OPMLSubscription(title: "Zebra", rssURL: URL(string: "https://example.com/zebra.xml")!),
        ])
        #expect(preview.alreadySubscribedCount == 0)
        #expect(preview.duplicateEntryCount == 0)
        #expect(preview.invalidEntryCount == 0)
    }

    @Test
    func sampleOPMLUsesTheFutureOfLifePodcastFeedRatherThanItsPostArchive() throws {
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let sampleURL = repositoryRootURL
            .appending(path: "SampleData", directoryHint: .isDirectory)
            .appending(path: "gpodder-sample-subscriptions.opml")

        let preview = try service.importPreview(
            data: Data(contentsOf: sampleURL),
            existingSubscriptions: []
        )

        #expect(preview.subscriptionsToAdd.contains {
            $0.rssURL.absoluteString == "https://feeds.transistor.fm/future-of-life-institute-podcast-4e4d1fa5-a878-4cb2-91be-91c3ce266dfd"
        })
        #expect(!preview.subscriptionsToAdd.contains {
            $0.rssURL.absoluteString == "https://futureoflife.org/podcast/feed/"
        })
    }
}
