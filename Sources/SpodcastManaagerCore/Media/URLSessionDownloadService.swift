import Foundation

public struct URLSessionDownloadService: DownloadService {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        let resolvedMediaURL = try await resolvedMediaURL(for: episode.enclosureURL)
        let request = URLRequest(url: resolvedMediaURL)
        let (temporaryURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let destinationURL = workspaceURL.appending(path: fileName(for: episode, mediaURL: resolvedMediaURL), directoryHint: .notDirectory)

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

    private func fileName(for episode: Episode, mediaURL: URL) -> String {
        let enclosureExtension = mediaURL.pathExtension.isEmpty ? "bin" : mediaURL.pathExtension
        return sanitizedBaseName(for: episode.title) + "." + enclosureExtension.lowercased()
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

    private func sanitizedBaseName(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = trimmed.components(separatedBy: disallowed)
        let collapsed = components.joined(separator: "-").replacingOccurrences(of: " ", with: "_")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
