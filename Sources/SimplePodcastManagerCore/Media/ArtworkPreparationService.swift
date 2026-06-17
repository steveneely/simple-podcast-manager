import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol ArtworkPreparationService: Sendable {
    func prepareArtwork(from artworkURL: URL, in workspaceURL: URL) async throws -> URL
}

public struct PodcastArtworkPreparationService: ArtworkPreparationService {
    private static let maxCoverArtPixelSize = 400
    private static let coverArtCompressionQuality = 0.72

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func prepareArtwork(from artworkURL: URL, in workspaceURL: URL) async throws -> URL {
        let (data, response) = try await session.data(from: artworkURL)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ArtworkPreparationError.requestFailed
        }

        let artworkDirectoryURL = workspaceURL.appending(path: "artwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artworkDirectoryURL, withIntermediateDirectories: true)
        let destinationURL = artworkDirectoryURL.appending(path: stableArtworkFileName(for: artworkURL), directoryHint: .notDirectory)

        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maxCoverArtPixelSize,
                ] as CFDictionary
            ),
            let imageDestination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw ArtworkPreparationError.invalidImage
        }

        CGImageDestinationAddImage(
            imageDestination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: Self.coverArtCompressionQuality,
            ] as CFDictionary
        )

        guard CGImageDestinationFinalize(imageDestination) else {
            throw ArtworkPreparationError.invalidImage
        }

        return destinationURL
    }

    private func stableArtworkFileName(for artworkURL: URL) -> String {
        let data = Data(artworkURL.absoluteString.utf8)
        let hash = data.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)).multipliedReportingOverflow(by: 1_099_511_628_211).partialValue
        }
        return "\(String(hash, radix: 16)).jpg"
    }
}

public enum ArtworkPreparationError: Error, Sendable {
    case requestFailed
    case invalidImage
}
