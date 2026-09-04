import Foundation
import SimplePodcastManagerCore

public enum PodcastDraftError: Error, Equatable, Sendable {
    case invalidRSSURL
}

public struct PodcastDraft: Equatable, Sendable {
    public var id: UUID?
    public var rssURLString: String
    public var artworkURL: URL?
    public var currentTitle: String?
    public var isEnabled: Bool
    public var includesInAutomaticDownloads: Bool

    public init(
        id: UUID? = nil,
        rssURLString: String = "",
        artworkURL: URL? = nil,
        currentTitle: String? = nil,
        isEnabled: Bool = true,
        includesInAutomaticDownloads: Bool = true
    ) {
        self.id = id
        self.rssURLString = rssURLString
        self.artworkURL = artworkURL
        self.currentTitle = currentTitle
        self.isEnabled = isEnabled
        self.includesInAutomaticDownloads = includesInAutomaticDownloads
    }

    public init(subscription: PodcastSubscription) {
        self.id = subscription.id
        self.rssURLString = subscription.rssURL.absoluteString
        self.artworkURL = subscription.artworkURL
        self.currentTitle = subscription.title
        self.isEnabled = subscription.isEnabled
        self.includesInAutomaticDownloads = subscription.includesInAutomaticDownloads
    }

    public var canSave: Bool {
        let normalizedURLString = rssURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = URL(string: normalizedURLString)?.scheme?.lowercased()

        return id != nil || scheme == "http" || scheme == "https"
    }

    public func resolvedRSSURL() throws -> URL {
        guard
            let rssURL = URL(string: rssURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = rssURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw PodcastDraftError.invalidRSSURL
        }

        return rssURL
    }

    public func makeSubscription(title: String, artworkURL: URL?, description: String?) throws -> PodcastSubscription {
        return PodcastSubscription(
            id: id ?? UUID(),
            title: title,
            rssURL: try resolvedRSSURL(),
            artworkURL: artworkURL,
            description: description,
            isEnabled: isEnabled,
            includesInAutomaticDownloads: includesInAutomaticDownloads
        )
    }
}
