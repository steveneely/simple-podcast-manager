import SwiftUI

struct PodcastArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    init(artworkURL: URL?, size: CGFloat, cornerRadius: CGFloat = 10) {
        self.artworkURL = artworkURL
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
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
