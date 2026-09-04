import Foundation
import SimplePodcastManagerCore

struct PodcastSearchSubscriptionMatcher {
    private let feedURLIdentities: Set<String>
    private let titles: Set<String>

    init(subscriptions: [PodcastSubscription]) {
        self.feedURLIdentities = Set(
            subscriptions.map { FeedURLIdentity.normalized($0.rssURL) }
        )
        self.titles = Set(subscriptions.map { Self.normalizedTitle($0.title) })
    }

    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        feedURLIdentities.contains(FeedURLIdentity.normalized(result.feedURL))
            || titles.contains(Self.normalizedTitle(result.title))
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
