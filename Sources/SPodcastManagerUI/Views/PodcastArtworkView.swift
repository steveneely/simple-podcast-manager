import AppKit
import SPodcastManagerCore
import SwiftUI

struct PodcastArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    @StateObject private var loader = ArtworkLoader()

    init(artworkURL: URL?, size: CGFloat, cornerRadius: CGFloat = 10) {
        self.artworkURL = artworkURL
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
        .task(id: artworkURL) {
            await loader.load(from: artworkURL)
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

    func load(from url: URL?) async {
        guard let url else {
            image = nil
            return
        }

        if let cachedImage = Self.memoryCache.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
        if let cachedResponse = CachedHTTPSession.shared.configuration.urlCache?.cachedResponse(for: request),
           let cachedImage = NSImage(data: cachedResponse.data) {
            Self.memoryCache.setObject(cachedImage, forKey: url as NSURL)
            image = cachedImage
            return
        }

        do {
            let (data, response) = try await CachedHTTPSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode),
                  let fetchedImage = NSImage(data: data) else {
                image = nil
                return
            }

            Self.memoryCache.setObject(fetchedImage, forKey: url as NSURL)
            if let cache = CachedHTTPSession.shared.configuration.urlCache {
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            }
            image = fetchedImage
        } catch {
            image = nil
        }
    }
}
