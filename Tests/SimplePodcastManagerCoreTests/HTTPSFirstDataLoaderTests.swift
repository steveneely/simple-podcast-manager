import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct HTTPSFirstDataLoaderTests {
    @Test
    func upgradesHTTPURLToHTTPSBeforeLoadingData() async throws {
        let httpURL = URL(string: "http://images.example.com/secure-artwork.jpg")!
        let httpsURL = URL(string: "https://images.example.com/secure-artwork.jpg")!
        DataURLProtocolStub.stub(url: httpsURL, data: Data("secure artwork".utf8))
        let loader = makeLoader()

        let data = try await loader.data(from: httpURL, allowsInsecureHTTP: false)

        #expect(data == Data("secure artwork".utf8))
    }

    @Test
    func requiresPermissionWhenHTTPResourceCannotBeLoadedOverHTTPS() async {
        let httpURL = URL(string: "http://images.example.com/insecure-artwork.jpg")!
        let httpsURL = URL(string: "https://images.example.com/insecure-artwork.jpg")!
        DataURLProtocolStub.stub(url: httpsURL, data: Data(), statusCode: 404)
        let loader = makeLoader()

        await #expect(throws: HTTPDataResourceLoadingError.insecureDownloadRequiresPermission) {
            try await loader.data(from: httpURL, allowsInsecureHTTP: false)
        }
    }

    @Test
    func approvedFallbackLoadsTheOriginalHTTPResource() async throws {
        let httpURL = URL(string: "http://images.example.com/approved-artwork.jpg")!
        let httpsURL = URL(string: "https://images.example.com/approved-artwork.jpg")!
        DataURLProtocolStub.stub(url: httpsURL, data: Data(), statusCode: 404)
        let commandRecorder = DataDownloadCommandRecorder(data: Data("insecure artwork".utf8))
        let loader = makeLoader(commandRunner: StubDataDownloadCommandRunner(recorder: commandRecorder))

        let data = try await loader.data(from: httpURL, allowsInsecureHTTP: true)

        #expect(data == Data("insecure artwork".utf8))
        #expect(commandRecorder.arguments.last == httpURL.absoluteString)
    }

    @Test
    func secureResourceFailureDoesNotOfferHTTPFallback() async {
        let httpsURL = URL(string: "https://images.example.com/missing-artwork.jpg")!
        DataURLProtocolStub.stub(url: httpsURL, data: Data(), statusCode: 404)
        let loader = makeLoader()

        await #expect(throws: HTTPDataResourceLoadingError.requestFailed) {
            try await loader.data(from: httpsURL, allowsInsecureHTTP: true)
        }
    }

    private func makeLoader(
        commandRunner: any CommandRunning = StubDataDownloadCommandRunner()
    ) -> HTTPSFirstDataLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DataURLProtocolStub.self]
        return HTTPSFirstDataLoader(
            session: URLSession(configuration: configuration),
            commandRunner: commandRunner
        )
    }
}

private final class DataURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let store = DataURLProtocolStore()

    static func stub(url: URL, data: Data, statusCode: Int = 200) {
        store.set(data: data, statusCode: statusCode, for: url)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.store.stub(for: url) else {
            client?.urlProtocol(self, didFailWithError: HTTPDataResourceLoadingError.requestFailed)
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class DataURLProtocolStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [URL: (data: Data, statusCode: Int)] = [:]

    func set(data: Data, statusCode: Int, for url: URL) {
        lock.withLock { stubs[url] = (data, statusCode) }
    }

    func stub(for url: URL) -> (data: Data, statusCode: Int)? {
        lock.withLock { stubs[url] }
    }
}

private struct StubDataDownloadCommandRunner: CommandRunning {
    var recorder: DataDownloadCommandRecorder?

    init(recorder: DataDownloadCommandRecorder? = nil) {
        self.recorder = recorder
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandRunResult {
        guard let recorder else {
            return CommandRunResult(terminationStatus: 1, standardOutput: "", standardError: "")
        }
        try recorder.record(arguments: arguments)
        return CommandRunResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }
}

private final class DataDownloadCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private var recordedArguments: [String] = []

    init(data: Data) {
        self.data = data
    }

    var arguments: [String] {
        lock.withLock { recordedArguments }
    }

    func record(arguments: [String]) throws {
        guard let outputIndex = arguments.firstIndex(of: "--output"),
              arguments.indices.contains(outputIndex + 1) else {
            throw HTTPDataResourceLoadingError.insecureDownloadFailed
        }

        try data.write(to: URL(fileURLWithPath: arguments[outputIndex + 1]))
        lock.withLock { recordedArguments = arguments }
    }
}
