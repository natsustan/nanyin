import AppKit
import NanyinKit

/// Cover art, decoded once and kept in memory, shared by every view that
/// shows it and by Now Playing. Downloads go through `URLCache.shared` and
/// the app's configured `HTTPTransport`.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    var transport: HTTPTransport = .shared
    private let cache = NSCache<NSURL, NSImage>()
    private var loading: [URL: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 400
    }

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The image at `url`; concurrent requests for one URL share a download.
    func image(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        let transport = self.transport
        let task = Task<NSImage?, Never> {
            guard let session = try? transport.currentSession(),
                  let (data, _) = try? await session.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
