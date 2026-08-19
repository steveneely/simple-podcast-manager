import AppKit
import SimplePodcastManagerCore
import SwiftUI

struct PodcastArtworkView: View {
    let artworkURL: URL?
    let allowsInsecureHTTP: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
    @StateObject private var loader = ArtworkLoader()

    init(
        artworkURL: URL?,
        allowsInsecureHTTP: Bool,
        size: CGFloat,
        cornerRadius: CGFloat = 10
    ) {
        self.artworkURL = artworkURL
        self.allowsInsecureHTTP = allowsInsecureHTTP
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .task(id: ArtworkLoadRequest(url: artworkURL, allowsInsecureHTTP: allowsInsecureHTTP)) {
            await loader.load(from: artworkURL, allowsInsecureHTTP: allowsInsecureHTTP)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.accentColor.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

@MainActor
private final class ArtworkLoader: ObservableObject {
    @Published var image: NSImage?

    private static let memoryCache = NSCache<NSURL, NSImage>()
    private let dataLoader = HTTPSFirstDataLoader(session: CachedHTTPSession.shared)

    func load(from url: URL?, allowsInsecureHTTP: Bool) async {
        guard let url else {
            image = nil
            return
        }

        if let cachedImage = Self.memoryCache.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        do {
            let data = try await dataLoader.data(
                from: url,
                allowsInsecureHTTP: allowsInsecureHTTP
            )
            guard let fetchedImage = NSImage(data: data) else {
                image = nil
                return
            }

            Self.memoryCache.setObject(fetchedImage, forKey: url as NSURL)
            image = fetchedImage
        } catch {
            image = nil
        }
    }
}

private struct ArtworkLoadRequest: Hashable {
    var url: URL?
    var allowsInsecureHTTP: Bool
}
