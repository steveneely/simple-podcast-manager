import Foundation

public protocol HTTPDataResourceLoading: Sendable {
    func data(from sourceURL: URL, allowsInsecureHTTP: Bool) async throws -> Data
}

public struct HTTPSFirstDataLoader: HTTPDataResourceLoading {
    private let session: URLSession
    private let commandRunner: any CommandRunning
    private let curlExecutableURL: URL

    public init(
        session: URLSession = .shared,
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        curlExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/curl")
    ) {
        self.session = session
        self.commandRunner = commandRunner
        self.curlExecutableURL = curlExecutableURL
    }

    public func data(from sourceURL: URL, allowsInsecureHTTP: Bool) async throws -> Data {
        do {
            return try await loadSecurely(from: Self.secureVersion(of: sourceURL))
        } catch {
            guard Self.shouldOfferInsecureFallback(for: sourceURL, after: error) else {
                throw error
            }

            guard allowsInsecureHTTP else {
                throw HTTPDataResourceLoadingError.insecureDownloadRequiresPermission
            }

            return try await loadInsecurely(from: sourceURL)
        }
    }

    public static func secureVersion(of url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func loadSecurely(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPDataResourceLoadingError.requestFailed
        }
        return data
    }

    private func loadInsecurely(from url: URL) async throws -> Data {
        let temporaryURL = FileManager.default.temporaryDirectory.appending(
            path: "simple-podcast-manager-http-\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let result = try await commandRunner.run(
            executableURL: curlExecutableURL,
            arguments: [
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--proto", "=http,https",
                "--proto-redir", "=http,https",
                "--output", temporaryURL.path,
                url.absoluteString,
            ]
        )
        guard result.terminationStatus == 0,
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw HTTPDataResourceLoadingError.insecureDownloadFailed
        }

        return try Data(contentsOf: temporaryURL)
    }

    public static func shouldOfferInsecureFallback(for sourceURL: URL, after error: Error) -> Bool {
        if sourceURL.scheme?.lowercased() == "http" {
            return true
        }

        return (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection
    }
}

public enum HTTPDataResourceLoadingError: LocalizedError, Equatable, Sendable {
    case requestFailed
    case insecureDownloadRequiresPermission
    case insecureDownloadFailed

    public var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "The resource could not be downloaded."
        case .insecureDownloadRequiresPermission:
            return "This episode includes content that is only available over an insecure HTTP connection."
        case .insecureDownloadFailed:
            return "The insecure resource download failed."
        }
    }
}
