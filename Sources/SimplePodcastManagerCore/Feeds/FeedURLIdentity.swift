import Foundation

public enum FeedURLIdentity {
    public static func normalized(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }

        let scheme = components.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            components.scheme = "https"
            components.host = components.host?.lowercased()
            if components.port == 80 || components.port == 443 {
                components.port = nil
            }
        }

        components.fragment = nil

        let path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            components.percentEncodedPath = String(path.dropLast())
        }

        return components.string ?? url.absoluteString
    }
}
