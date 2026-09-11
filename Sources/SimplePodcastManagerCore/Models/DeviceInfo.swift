import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var rootURL: URL
    public var podcastDirectoryURL: URL
    public var playlistDirectoryURL: URL

    public var id: String {
        rootURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public init(
        name: String,
        rootURL: URL,
        podcastDirectoryURL: URL,
        playlistDirectoryURL: URL? = nil
    ) {
        self.name = name
        self.rootURL = rootURL
        self.podcastDirectoryURL = podcastDirectoryURL
        self.playlistDirectoryURL = playlistDirectoryURL ?? podcastDirectoryURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case rootURL
        case podcastDirectoryURL
        case playlistDirectoryURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        rootURL = try container.decode(URL.self, forKey: .rootURL)
        podcastDirectoryURL = try container.decode(URL.self, forKey: .podcastDirectoryURL)
        playlistDirectoryURL = try container.decodeIfPresent(URL.self, forKey: .playlistDirectoryURL)
            ?? podcastDirectoryURL
    }
}
