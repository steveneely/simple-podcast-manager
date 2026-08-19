import Foundation
import Testing
@testable import SimplePodcastManagerCore

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

    @Test
    func upgradesHTTPEnclosureToHTTPSBeforeDownloading() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]
        let httpURL = URL(string: "http://cdn.example.com/secure-upgrade.mp3")!
        let httpsURL = URL(string: "https://cdn.example.com/secure-upgrade.mp3")!
        DownloadURLProtocolStub.stub(url: httpsURL, bodyData: Data("secure audio".utf8), contentType: "audio/mpeg")

        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let service = URLSessionDownloadService(session: URLSession(configuration: configuration))

        let fileURL = try await service.download(
            episode(enclosureURL: httpURL),
            into: workspaceURL,
            allowsInsecureHTTP: false
        )

        #expect(try Data(contentsOf: fileURL) == Data("secure audio".utf8))
    }

    @Test
    func requiresPermissionWhenHTTPEnclosureCannotBeDownloadedOverHTTPS() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]
        let httpURL = URL(string: "http://cdn.example.com/requires-permission.mp3")!
        let httpsURL = URL(string: "https://cdn.example.com/requires-permission.mp3")!
        DownloadURLProtocolStub.stub(
            url: httpsURL,
            bodyData: Data(),
            contentType: "text/plain",
            statusCode: 404
        )

        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let service = URLSessionDownloadService(session: URLSession(configuration: configuration))

        await #expect(throws: DownloadServiceError.insecureDownloadRequiresPermission) {
            try await service.download(
                episode(enclosureURL: httpURL),
                into: workspaceURL,
                allowsInsecureHTTP: false
            )
        }
    }

    @Test
    func approvedHTTPFallbackDownloadsOnlyTheOriginalEpisodeURL() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]
        let httpURL = URL(string: "http://cdn.example.com/approved-fallback.mp3")!
        let httpsURL = URL(string: "https://cdn.example.com/approved-fallback.mp3")!
        DownloadURLProtocolStub.stub(
            url: httpsURL,
            bodyData: Data(),
            contentType: "text/plain",
            statusCode: 404
        )
        let commandRecorder = DownloadCommandRecorder(downloadedData: Data("insecure audio".utf8))
        let service = URLSessionDownloadService(
            session: URLSession(configuration: configuration),
            commandRunner: StubDownloadCommandRunner(recorder: commandRecorder)
        )
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let fileURL = try await service.download(
            episode(enclosureURL: httpURL),
            into: workspaceURL,
            allowsInsecureHTTP: true
        )

        #expect(try Data(contentsOf: fileURL) == Data("insecure audio".utf8))
        #expect(commandRecorder.arguments.last == httpURL.absoluteString)
        #expect(commandRecorder.arguments.contains("=http,https"))
    }

    @Test
    func secureHTTPFailureDoesNotOfferAnInsecureFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]
        let httpsURL = URL(string: "https://cdn.example.com/secure-failure.mp3")!
        DownloadURLProtocolStub.stub(
            url: httpsURL,
            bodyData: Data(),
            contentType: "text/plain",
            statusCode: 404
        )
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let service = URLSessionDownloadService(session: URLSession(configuration: configuration))

        await #expect(throws: DownloadServiceError.requestFailed(statusCode: 404)) {
            try await service.download(
                episode(enclosureURL: httpsURL),
                into: workspaceURL,
                allowsInsecureHTTP: true
            )
        }
    }

    @Test
    func failedApprovedHTTPFallbackRemovesItsPartialFile() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocolStub.self]
        let httpURL = URL(string: "http://cdn.example.com/failed-fallback.mp3")!
        let httpsURL = URL(string: "https://cdn.example.com/failed-fallback.mp3")!
        DownloadURLProtocolStub.stub(
            url: httpsURL,
            bodyData: Data(),
            contentType: "text/plain",
            statusCode: 404
        )
        let commandRecorder = DownloadCommandRecorder(
            downloadedData: Data("partial audio".utf8),
            terminationStatus: 22
        )
        let service = URLSessionDownloadService(
            session: URLSession(configuration: configuration),
            commandRunner: StubDownloadCommandRunner(recorder: commandRecorder)
        )
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        await #expect(throws: DownloadServiceError.insecureDownloadFailed) {
            try await service.download(
                episode(enclosureURL: httpURL),
                into: workspaceURL,
                allowsInsecureHTTP: true
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path).isEmpty)
    }

    private func makeWorkspace() throws -> URL {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }

    private func episode(enclosureURL: URL) -> Episode {
        Episode(
            id: UUID().uuidString,
            podcastTitle: "Example Podcast",
            title: "Example Episode",
            enclosureURL: enclosureURL,
            sourceFeedURL: URL(string: "https://example.com/feed.xml")!
        )
    }
}

private final class DownloadURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let store = DownloadStubStore()

    static func stub(url: URL, body: String, contentType: String = "text/html") {
        guard let data = body.data(using: .utf8) else { return }
        store.set(data, contentType: contentType, for: url.absoluteString)
    }

    static func stub(url: URL, bodyData: Data, contentType: String, statusCode: Int = 200) {
        store.set(bodyData, contentType: contentType, statusCode: statusCode, for: url.absoluteString)
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
            statusCode: response.statusCode,
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
    private var responses: [String: (body: Data, contentType: String, statusCode: Int)] = [:]

    func set(_ body: Data, contentType: String, statusCode: Int = 200, for urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[urlString] = (body, contentType, statusCode)
    }

    func response(for urlString: String) -> (body: Data, contentType: String, statusCode: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return responses[urlString]
    }
}

private struct StubDownloadCommandRunner: CommandRunning {
    let recorder: DownloadCommandRecorder

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        try recorder.record(arguments: arguments)
        return CommandRunResult(
            terminationStatus: recorder.terminationStatus,
            standardOutput: "",
            standardError: ""
        )
    }
}

private final class DownloadCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let downloadedData: Data
    let terminationStatus: Int32
    private var recordedArguments: [String] = []

    init(downloadedData: Data, terminationStatus: Int32 = 0) {
        self.downloadedData = downloadedData
        self.terminationStatus = terminationStatus
    }

    var arguments: [String] {
        lock.withLock { recordedArguments }
    }

    func record(arguments: [String]) throws {
        guard let outputArgumentIndex = arguments.firstIndex(of: "--output"),
              arguments.indices.contains(outputArgumentIndex + 1) else {
            throw DownloadServiceError.missingDownloadLocation
        }

        try downloadedData.write(to: URL(fileURLWithPath: arguments[outputArgumentIndex + 1]))
        lock.withLock { recordedArguments = arguments }
    }
}
