import Foundation
import Testing
@testable import SPodcastManagerCore

struct URLSessionDownloadServiceTests {
    @Test
    func resolvesTransistorEmbedToMediaURLBeforeDownloading() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]

        let embedURL = URL(string: "https://share.transistor.fm/e/14615be3/?color=444444&background=ffffff")!
        let mediaURL = URL(string: "https://media.transistor.fm/14615be3/4192276c.mp3")!

        DownloadURLProtocolStub.stub(
            url: embedURL,
            body: """
            <div x-data="transistor.audioEmbedPlayer({&quot;episodes&quot;:[{&quot;trackable_media_url&quot;:&quot;https://media.transistor.fm/14615be3/4192276c.mp3&quot;}]} )"></div>
            """
        )
        DownloadURLProtocolStub.stub(url: mediaURL, bodyData: Data("audio".utf8), contentType: "audio/mpeg")

        let service = URLSessionDownloadService(session: URLSession(configuration: configuration))
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let fileURL = try await service.download(
            Episode(
                id: "ep-1",
                podcastTitle: "Example Podcast",
                title: "Episode 1",
                publicationDate: Date(timeIntervalSince1970: 1_713_713_388),
                enclosureURL: embedURL,
                sourceFeedURL: URL(string: "https://example.com/feed.xml")!
            ),
            into: workspaceURL
        )

        #expect(fileURL.lastPathComponent == "2024.04.21-Episode 1-(Example Podcast).mp3")
        #expect(fileURL.pathExtension == "mp3")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == Data("audio".utf8))
    }
}

private final class DownloadURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let store = DownloadStubStore()

    static func stub(url: URL, body: String, contentType: String = "text/html") {
        guard let data = body.data(using: .utf8) else { return }
        store.set(data, contentType: contentType, for: url.absoluteString)
    }

    static func stub(url: URL, bodyData: Data, contentType: String) {
        store.set(bodyData, contentType: contentType, for: url.absoluteString)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let response = Self.store.response(for: url.absoluteString)
        else {
            client?.urlProtocol(self, didFailWithError: DownloadServiceError.invalidResponse)
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": response.contentType]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class DownloadStubStore: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (body: Data, contentType: String)] = [:]

    func set(_ body: Data, contentType: String, for urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[urlString] = (body, contentType)
    }

    func response(for urlString: String) -> (body: Data, contentType: String)? {
        lock.lock()
        defer { lock.unlock() }
        return responses[urlString]
    }
}
