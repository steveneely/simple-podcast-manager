import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol ArtworkPreparationService: Sendable {
    func prepareArtwork(
        from artworkURL: URL,
        in workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> URL
}

public struct PodcastArtworkPreparationService: ArtworkPreparationService {
    private static let maxCoverArtPixelSize = 400
    private static let coverArtCompressionQuality = 0.72

    private let dataLoader: any HTTPDataResourceLoading

    public init(
        session: URLSession = .shared,
        commandRunner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.dataLoader = HTTPSFirstDataLoader(session: session, commandRunner: commandRunner)
    }

    public init(dataLoader: any HTTPDataResourceLoading) {
        self.dataLoader = dataLoader
    }

    public func prepareArtwork(
        from artworkURL: URL,
        in workspaceURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws -> URL {
        let data = try await dataLoader.data(
            from: artworkURL,
            allowsInsecureHTTP: allowsInsecureHTTP
        )

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
    case invalidImage
}
