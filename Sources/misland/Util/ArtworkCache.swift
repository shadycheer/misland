import AppKit

/// Shared, thread-safe artwork cache + network loader, used by both the
/// now-playing view and the playlist browser.
///
/// Network covers (Spotify album art / playlist images) go through a URLSession
/// backed by an on-disk + in-memory `URLCache`, and decoded images are memoized
/// by URL in an `NSCache`. Result: the first fetch of a cover costs one request;
/// every later display of the same cover (re-selecting a track, scrolling back to
/// a row, even across launches via the disk cache) is instant. Duplicate inflight
/// requests for the same URL are coalesced.
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var inflight: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 128 << 20, diskPath: "misland-art")
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
        cache.countLimit = 500
    }

    /// Synchronously return an already-decoded image if present.
    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    /// Load an image for `urlString`, memoized by URL. Completion is always on
    /// the main thread. Concurrent calls for the same URL share one request.
    func image(for urlString: String, completion: @escaping (NSImage?) -> Void) {
        if let img = cached(urlString) {
            DispatchQueue.main.async { completion(img) }
            return
        }
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        lock.lock()
        if inflight[urlString] != nil {
            inflight[urlString]?.append(completion)
            lock.unlock()
            return
        }
        inflight[urlString] = [completion]
        lock.unlock()

        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let image = data.flatMap { NSImage(data: $0) }
            if let image { self.cache.setObject(image, forKey: urlString as NSString) }
            self.lock.lock()
            let waiters = self.inflight.removeValue(forKey: urlString) ?? []
            self.lock.unlock()
            DispatchQueue.main.async { waiters.forEach { $0(image) } }
        }.resume()
    }

    /// Memoize an image produced by a synchronous `loader` (e.g. local Apple
    /// Music artwork via ScriptingBridge), keyed by `key`. The loader runs once
    /// off-main; concurrent requests for the same key share it. Completion on main.
    func image(key: String, loader: @escaping () -> NSImage?, completion: @escaping (NSImage?) -> Void) {
        if let img = cached(key) {
            DispatchQueue.main.async { completion(img) }
            return
        }
        lock.lock()
        if inflight[key] != nil {
            inflight[key]?.append(completion)
            lock.unlock()
            return
        }
        inflight[key] = [completion]
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let image = loader()
            if let image { self.cache.setObject(image, forKey: key as NSString) }
            self.lock.lock()
            let waiters = self.inflight.removeValue(forKey: key) ?? []
            self.lock.unlock()
            DispatchQueue.main.async { waiters.forEach { $0(image) } }
        }
    }
}
