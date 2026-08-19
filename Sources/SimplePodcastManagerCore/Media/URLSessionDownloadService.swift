import Foundation

public struct URLSessionDownloadService: DownloadService {
    public let session: URLSession
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

    public func download(
        _ episode: Episode,
        into workspaceURL: URL,
        allowsInsecureHTTP: Bool = false
    ) async throws -> URL {
        var insecureFallbackURL = episode.enclosureURL

        do {
            let secureEnclosureURL = secureVersion(of: episode.enclosureURL)
            let resolvedMediaURL = try await resolvedMediaURL(for: secureEnclosureURL)
            if resolvedMediaURL != secureEnclosureURL {
                insecureFallbackURL = resolvedMediaURL
            }
            let secureMediaURL = secureVersion(of: resolvedMediaURL)
            return try await downloadSecurely(episode, from: secureMediaURL, into: workspaceURL)
        } catch {
            guard shouldOfferInsecureFallback(for: insecureFallbackURL, after: error) else {
                throw error
            }

            guard allowsInsecureHTTP else {
                throw DownloadServiceError.insecureDownloadRequiresPermission
            }

            return try await downloadInsecurely(
                episode,
                from: insecureFallbackURL,
                into: workspaceURL
            )
        }
    }

    private func downloadSecurely(
        _ episode: Episode,
        from mediaURL: URL,
        into workspaceURL: URL
    ) async throws -> URL {
        let (temporaryURL, response) = try await session.download(for: URLRequest(url: mediaURL))
        try validate(response)

        let destinationURL = workspaceURL.appending(
            path: fileName(for: episode, mediaURL: mediaURL),
            directoryHint: .notDirectory
        )
        return try moveDownloadedFile(from: temporaryURL, to: destinationURL)
    }

    private func downloadInsecurely(
        _ episode: Episode,
        from mediaURL: URL,
        into workspaceURL: URL
    ) async throws -> URL {
        // Keep ATS enabled for the app and isolate HTTP to this explicitly approved command.
        let temporaryURL = workspaceURL.appending(
            path: "insecure-download-\(UUID().uuidString).tmp",
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
                mediaURL.absoluteString,
            ]
        )
        guard result.terminationStatus == 0,
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw DownloadServiceError.insecureDownloadFailed
        }

        let destinationURL = workspaceURL.appending(
            path: fileName(for: episode, mediaURL: mediaURL),
            directoryHint: .notDirectory
        )
        return try moveDownloadedFile(from: temporaryURL, to: destinationURL)
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func moveDownloadedFile(from temporaryURL: URL, to destinationURL: URL) throws -> URL {
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            throw DownloadServiceError.missingDownloadLocation
        }
    }

    private func secureVersion(of url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func shouldOfferInsecureFallback(for mediaURL: URL, after error: Error) -> Bool {
        if mediaURL.scheme?.lowercased() == "http" {
            return true
        }

        return (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection
    }

    private func fileName(for episode: Episode, mediaURL: URL) -> String {
        let enclosureExtension = mediaURL.pathExtension.isEmpty ? "bin" : mediaURL.pathExtension
        return EpisodeFileName.fileName(for: episode, fileExtension: enclosureExtension)
    }

    private func resolvedMediaURL(for enclosureURL: URL) async throws -> URL {
        guard enclosureURL.host?.lowercased() == "share.transistor.fm", enclosureURL.path.hasPrefix("/e/") else {
            return enclosureURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: enclosureURL))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        guard
            let html = String(data: data, encoding: .utf8),
            let mediaURL = extractTransistorMediaURL(from: html)
        else {
            throw DownloadServiceError.invalidResponse
        }

        return mediaURL
    }

    private func extractTransistorMediaURL(from html: String) -> URL? {
        let decodedHTML = html
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")

        let pattern = #""trackable_media_url":"([^"]+)""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(in: decodedHTML, options: [], range: NSRange(decodedHTML.startIndex..., in: decodedHTML)),
            let urlRange = Range(match.range(at: 1), in: decodedHTML)
        else {
            return nil
        }

        let urlString = decodedHTML[urlRange].replacingOccurrences(of: "\\/", with: "/")
        return URL(string: urlString)
    }
}
