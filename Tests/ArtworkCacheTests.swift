import AppKit
import Foundation

@main
private enum ArtworkCacheTests {
    static func main() async {
        await foregroundRequestsShareDownloadAndDecode()
        await cancellingOneForegroundWaiterKeepsSharedWorkAlive()
        await differentRenditionsShareDownloadButDecodeSeparately()
        await savedAlbumsUseHotAndColdPrefetchTiers()
        await replacingScopeCancelsObsoleteWork()
        await replacedDecodeCannotPopulateMemoryCache()
        await replacingScopeRetainsSharedWork()
        await foregroundPreemptsSpeculativeNetworkWork()
        await schedulerRespectsConcurrencyLimits()
        await pendingSpeculationIsBounded()
        print("Artwork cache tests passed")
    }

    @MainActor
    private static func foregroundRequestsShareDownloadAndDecode() async {
        let loader = RecordingArtworkDataLoader()
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(
            dataLoader: loader,
            decoder: decoder,
            policy: .testing
        )
        let url = URL(string: "https://i.scdn.co/image/shared")!

        async let first = cache.image(for: url, targetSize: 88)
        async let second = cache.image(for: url, targetSize: 88)
        let images = await [first, second]
        let downloadCount = await loader.callCount
        let decodeCount = await decoder.callCount

        expect(images.allSatisfy { $0 != nil }, "foreground requests return an image")
        expect(downloadCount == 1, "same URL downloads once")
        expect(decodeCount == 1, "same rendition decodes once")
        expect(
            cache.cachedImage(for: url, targetSize: 88) != nil,
            "decoded image is synchronously cached"
        )
    }

    @MainActor
    private static func cancellingOneForegroundWaiterKeepsSharedWorkAlive() async {
        let loader = DelayedArtworkDataLoader(delay: .milliseconds(100))
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .testing)
        let url = URL(string: "https://i.scdn.co/image/cancel-one")!
        let first = Task { @MainActor in
            await cache.image(for: url, targetSize: 88)
        }
        let second = Task { @MainActor in
            await cache.image(for: url, targetSize: 88)
        }

        await waitUntil { await loader.startedURLs.count == 1 }
        first.cancel()
        let firstImage = await first.value
        let secondImage = await second.value
        let starts = await loader.startedURLs

        expect(firstImage == nil, "cancelled foreground waiter receives no image")
        expect(secondImage != nil, "remaining foreground waiter receives the shared image")
        expect(starts == [url], "cancelling one waiter does not restart the download")
    }

    @MainActor
    private static func differentRenditionsShareDownloadButDecodeSeparately() async {
        let loader = RecordingArtworkDataLoader()
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .testing)
        let url = URL(string: "https://i.scdn.co/image/sizes")!

        async let small = cache.image(for: url, targetSize: 32)
        async let large = cache.image(for: url, targetSize: 112)
        let images = await [small, large]
        let downloadCount = await loader.callCount
        let pixelSizes = await decoder.pixelSizes.sorted()

        expect(images.allSatisfy { $0 != nil }, "both renditions return images")
        expect(downloadCount == 1, "different renditions share one download")
        expect(pixelSizes == [64, 320], "different pixel buckets decode separately")
    }

    @MainActor
    private static func savedAlbumsUseHotAndColdPrefetchTiers() async {
        let loader = RecordingArtworkDataLoader()
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .testing)
        let urls = (0..<35).map { URL(string: "https://i.scdn.co/image/album-\($0)")! }

        cache.replacePrefetch(urls: urls, in: .savedAlbums)
        await waitUntil { await loader.callCount == 35 }
        try? await Task.sleep(for: .milliseconds(100))
        let decodeCount = await decoder.callCount

        expect(decodeCount == 30, "saved albums decode only the hot prefix")
        expect(
            cache.cachedImage(for: urls[29], targetSize: 160) != nil,
            "last hot artwork is decoded"
        )
        expect(
            cache.cachedImage(for: urls[30], targetSize: 160) == nil,
            "cold artwork only warms the byte cache"
        )
    }

    @MainActor
    private static func replacingScopeCancelsObsoleteWork() async {
        let loader = DelayedArtworkDataLoader(delay: .milliseconds(150))
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .serialTesting)
        let oldURL = URL(string: "https://i.scdn.co/image/old")!
        let newURL = URL(string: "https://i.scdn.co/image/new")!

        cache.replacePrefetch(urls: [oldURL], in: .detail)
        try? await Task.sleep(for: .milliseconds(20))
        cache.replacePrefetch(urls: [newURL], in: .detail)
        await waitUntil { await loader.startedURLs.contains(newURL) }
        try? await Task.sleep(for: .milliseconds(200))

        expect(
            cache.cachedImage(for: oldURL, targetSize: 88) == nil,
            "replaced scope does not publish obsolete artwork"
        )
        expect(
            cache.cachedImage(for: newURL, targetSize: 88) != nil,
            "replacement scope completes"
        )
    }

    @MainActor
    private static func replacedDecodeCannotPopulateMemoryCache() async {
        let loader = RecordingArtworkDataLoader()
        let decoder = SuspendedArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .serialTesting)
        let url = URL(string: "https://i.scdn.co/image/stale-decode")!

        cache.replacePrefetch(urls: [url], in: .detail)
        await waitUntil { await decoder.callCount == 1 }
        cache.replacePrefetch(urls: [], in: .detail)
        await decoder.resumeAll()
        try? await Task.sleep(for: .milliseconds(50))

        expect(
            cache.cachedImage(for: url, targetSize: 112) == nil,
            "replaced decode cannot populate the memory cache"
        )
    }

    @MainActor
    private static func replacingScopeRetainsSharedWork() async {
        let loader = DelayedArtworkDataLoader(delay: .milliseconds(100))
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .serialTesting)
        let url = URL(string: "https://i.scdn.co/image/retained")!

        cache.replacePrefetch(urls: [url], in: .detail)
        await waitUntil { await loader.startedURLs.count == 1 }
        cache.replacePrefetch(urls: [url], in: .detail)
        await waitUntil {
            await MainActor.run {
                cache.cachedImage(for: url, targetSize: 88) != nil
            }
        }
        let starts = await loader.startedURLs

        expect(starts == [url], "replacement retains shared in-flight work")
    }

    @MainActor
    private static func foregroundPreemptsSpeculativeNetworkWork() async {
        let loader = DelayedArtworkDataLoader(delay: .milliseconds(100))
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .serialTesting)
        let first = URL(string: "https://i.scdn.co/image/prefetch-1")!
        let second = URL(string: "https://i.scdn.co/image/prefetch-2")!
        let foreground = URL(string: "https://i.scdn.co/image/foreground")!

        cache.replacePrefetch(urls: [first, second], in: .library)
        await waitUntil { await loader.startedURLs.first == first }
        let image = await cache.image(for: foreground, targetSize: 88)
        let starts = await loader.startedURLs

        expect(image != nil, "foreground image completes")
        expect(starts.prefix(2) == [first, foreground], "foreground preempts queued speculation")
    }

    @MainActor
    private static func schedulerRespectsConcurrencyLimits() async {
        let loader = ConcurrencyArtworkDataLoader(delay: .milliseconds(30))
        let decoder = ConcurrencyArtworkDecoder(delay: .milliseconds(30))
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .testing)
        let urls = (0..<12).map { URL(string: "https://i.scdn.co/image/concurrency-\($0)")! }

        cache.replacePrefetch(urls: urls, in: .savedAlbums)
        await waitUntil { await decoder.callCount == urls.count }
        let maximumDownloads = await loader.maximumActiveCount
        let maximumDecodes = await decoder.maximumActiveCount

        expect(maximumDownloads <= 2, "network concurrency respects policy")
        expect(maximumDecodes <= 1, "decode concurrency respects policy")
    }

    @MainActor
    private static func pendingSpeculationIsBounded() async {
        let loader = RecordingArtworkDataLoader()
        let decoder = RecordingArtworkDecoder()
        let cache = ArtworkCache(dataLoader: loader, decoder: decoder, policy: .boundedTesting)
        let urls = (0..<10).map { URL(string: "https://i.scdn.co/image/bounded-\($0)")! }

        cache.replacePrefetch(urls: urls, in: .library)
        await waitUntil { await loader.callCount == 2 }
        try? await Task.sleep(for: .milliseconds(100))
        let callCount = await loader.callCount

        expect(callCount == 2, "pending hot speculation is capped")
    }

    private static func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(false, "condition completed before timeout")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}

private actor RecordingArtworkDataLoader: ArtworkDataLoading {
    private(set) var callCount = 0

    func data(for url: URL) async -> Data? {
        callCount += 1
        try? await Task.sleep(for: .milliseconds(20))
        return Data([1])
    }
}

private actor RecordingArtworkDecoder: ArtworkDecoding {
    private(set) var callCount = 0
    private(set) var pixelSizes: [Int] = []

    func image(from data: Data, maxPixelSize: Int) async -> NSImage? {
        callCount += 1
        pixelSizes.append(maxPixelSize)
        return NSImage(size: NSSize(width: maxPixelSize, height: maxPixelSize))
    }
}

private actor DelayedArtworkDataLoader: ArtworkDataLoading {
    private let delay: Duration
    private(set) var startedURLs: [URL] = []

    init(delay: Duration) {
        self.delay = delay
    }

    func data(for url: URL) async -> Data? {
        startedURLs.append(url)
        do {
            try await Task.sleep(for: delay)
            return Data([1])
        } catch {
            return nil
        }
    }
}

private actor SuspendedArtworkDecoder: ArtworkDecoding {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<NSImage?, Never>] = []

    func image(from data: Data, maxPixelSize: Int) async -> NSImage? {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: NSImage(size: NSSize(width: 320, height: 320)))
        }
    }
}

private actor ConcurrencyArtworkDataLoader: ArtworkDataLoading {
    private let delay: Duration
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func data(for url: URL) async -> Data? {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        try? await Task.sleep(for: delay)
        activeCount -= 1
        return Data([1])
    }
}

private actor ConcurrencyArtworkDecoder: ArtworkDecoding {
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func image(from data: Data, maxPixelSize: Int) async -> NSImage? {
        callCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        try? await Task.sleep(for: delay)
        activeCount -= 1
        return NSImage(size: NSSize(width: maxPixelSize, height: maxPixelSize))
    }
}

private extension ArtworkCache.Policy {
    static let testing = ArtworkCache.Policy(
        maximumNetworkRequests: 2,
        maximumDecodes: 1,
        maximumPendingHot: 64,
        maximumPendingCold: 64,
        decodedImageCostLimit: 8 * 1_024 * 1_024
    )

    static let serialTesting = ArtworkCache.Policy(
        maximumNetworkRequests: 1,
        maximumDecodes: 1,
        maximumPendingHot: 16,
        maximumPendingCold: 16,
        decodedImageCostLimit: 8 * 1_024 * 1_024
    )

    static let boundedTesting = ArtworkCache.Policy(
        maximumNetworkRequests: 1,
        maximumDecodes: 1,
        maximumPendingHot: 2,
        maximumPendingCold: 0,
        decodedImageCostLimit: 8 * 1_024 * 1_024
    )
}
