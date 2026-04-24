import Foundation

public enum CachedHTTPSession {
    public static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "simple-podcast-manager-url-cache"
        )
        return URLSession(configuration: configuration)
    }()
}
