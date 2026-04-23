import Foundation

public struct URLSessionDownloadService: DownloadService {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(_ episode: Episode, into workspaceURL: URL) async throws -> URL {
        let request = URLRequest(url: episode.enclosureURL)
        let (temporaryURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let destinationURL = workspaceURL.appending(path: fileName(for: episode), directoryHint: .notDirectory)

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

    private func fileName(for episode: Episode) -> String {
        let enclosureExtension = episode.enclosureURL.pathExtension.isEmpty ? "bin" : episode.enclosureURL.pathExtension
        return sanitizedBaseName(for: episode.title) + "." + enclosureExtension.lowercased()
    }

    private func sanitizedBaseName(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = trimmed.components(separatedBy: disallowed)
        let collapsed = components.joined(separator: "-").replacingOccurrences(of: " ", with: "_")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
