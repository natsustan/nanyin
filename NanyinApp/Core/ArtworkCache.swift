//
//  ArtworkCache.swift
//  Nanyin
//

import AppKit
import ImageIO

protocol ArtworkDataLoading: Sendable {
    func data(for url: URL) async -> Data?
}

protocol ArtworkDecoding: Sendable {
    func image(from data: Data, maxPixelSize: Int) async -> NSImage?
}

/// Shared artwork module: synchronous memory hits, foreground loading, and
/// scoped speculative scheduling backed by URLCache for restart/offline reuse.
@MainActor
final class ArtworkCache {
    enum PrefetchScope: Hashable {
        case homeRecentlyPlayed
        case homeTopArtists
        case library
        case savedAlbums
        case followedArtists
        case queue
        case detail
    }

    struct Policy {
        let maximumNetworkRequests: Int
        let maximumDecodes: Int
        let maximumPendingHot: Int
        let maximumPendingCold: Int
        let decodedImageCostLimit: Int

        static let live = Policy(
            maximumNetworkRequests: 4,
            maximumDecodes: 2,
            maximumPendingHot: 128,
            maximumPendingCold: 256,
            decodedImageCostLimit: 96 * 1_024 * 1_024
        )
    }

    static let shared = ArtworkCache.live()

    private enum Intent: Int {
        case cold = 1
        case hot = 2
        case foreground = 3
    }

    private struct ImageKey: Hashable {
        let url: URL
        let pixelSize: Int

        var cacheKey: NSString {
            "\(url.absoluteString)#\(pixelSize)" as NSString
        }
    }

    private final class Demand {
        let id: UUID
        let key: ImageKey?
        let url: URL
        let intent: Intent
        let scope: PrefetchScope?
        let generation: Int
        let batch: Int
        let position: Int
        let created: Int
        var continuation: CheckedContinuation<NSImage?, Never>?

        init(
            id: UUID = UUID(),
            key: ImageKey?,
            url: URL,
            intent: Intent,
            scope: PrefetchScope?,
            generation: Int,
            batch: Int,
            position: Int,
            created: Int,
            continuation: CheckedContinuation<NSImage?, Never>? = nil
        ) {
            self.id = id
            self.key = key
            self.url = url
            self.intent = intent
            self.scope = scope
            self.generation = generation
            self.batch = batch
            self.position = position
            self.created = created
            self.continuation = continuation
        }
    }

    private final class DataJob {
        let url: URL
        var consumers: Set<UUID> = []
        var runningID: UUID?
        var task: Task<Void, Never>?

        init(url: URL) {
            self.url = url
        }
    }

    private final class DecodeJob {
        let key: ImageKey
        let data: Data
        var consumers: Set<UUID> = []
        var runningID: UUID?
        var task: Task<Void, Never>?

        init(key: ImageKey, data: Data) {
            self.key = key
            self.data = data
        }
    }

    private struct ScopeState {
        let generation: Int
        var demandIDs: Set<UUID>
    }

    private let images = NSCache<NSString, NSImage>()
    private let dataLoader: any ArtworkDataLoading
    private let decoder: any ArtworkDecoding
    private let policy: Policy

    private var demands: [UUID: Demand] = [:]
    private var dataJobs: [URL: DataJob] = [:]
    private var decodeJobs: [ImageKey: DecodeJob] = [:]
    private var scopeStates: [PrefetchScope: ScopeState] = [:]
    private var scopeGenerations: [PrefetchScope: Int] = [:]
    private var activeNetworkRequests = 0
    private var activeDecodes = 0
    private var nextBatch = 0
    private var nextCreated = 0

    init(
        dataLoader: any ArtworkDataLoading,
        decoder: any ArtworkDecoding,
        policy: Policy = .live
    ) {
        self.dataLoader = dataLoader
        self.decoder = decoder
        self.policy = policy
        images.totalCostLimit = policy.decodedImageCostLimit
    }

    func cachedImage(for url: URL, targetSize: CGFloat) -> NSImage? {
        images.object(forKey: imageKey(url: url, targetSize: targetSize).cacheKey)
    }

    /// Foreground demand. It always outranks queued speculation and promotes
    /// matching speculative download/decode work instead of duplicating it.
    func image(for url: URL, targetSize: CGFloat) async -> NSImage? {
        let key = imageKey(url: url, targetSize: targetSize)
        if let image = images.object(forKey: key.cacheKey) {
            return image
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                addForegroundDemand(
                    id: id,
                    key: key,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelDemand(id)
            }
        }
    }

    /// Replaces prior speculative interest in this scope. Input order is the
    /// likelihood order: a bounded prefix is decoded, a bounded tail only
    /// warms URLCache, and the remainder is intentionally ignored.
    func replacePrefetch(
        urls: [URL],
        in scope: PrefetchScope
    ) {
        let replacedDemandIDs = scopeStates[scope]?.demandIDs ?? []
        scopeGenerations[scope, default: 0] += 1
        let generation = scopeGenerations[scope]!
        nextBatch += 1
        let batch = nextBatch
        let limits = prefetchLimits(for: scope)
        let targetSize = prefetchTargetSize(for: scope)

        var seen: Set<URL> = []
        var candidates: [URL] = []
        for url in urls where seen.insert(url).inserted {
            candidates.append(url)
            if candidates.count == limits.hot + limits.cold { break }
        }
        var state = ScopeState(generation: generation, demandIDs: [])
        for (position, url) in candidates.enumerated() {
            let intent: Intent = position < limits.hot ? .hot : .cold
            let key = intent == .hot ? imageKey(url: url, targetSize: targetSize) : nil
            if let key, images.object(forKey: key.cacheKey) != nil {
                continue
            }
            nextCreated += 1
            let demand = Demand(
                key: key,
                url: url,
                intent: intent,
                scope: scope,
                generation: generation,
                batch: batch,
                position: position,
                created: nextCreated
            )
            demands[demand.id] = demand
            state.demandIDs.insert(demand.id)
            attachDemand(demand)
        }
        scopeStates[scope] = state
        for id in replacedDemandIDs {
            cancelDemand(id, updateScope: false, shouldPump: false)
        }
        trimPendingSpeculation(intent: .hot, limit: policy.maximumPendingHot)
        trimPendingSpeculation(intent: .cold, limit: policy.maximumPendingCold)
        pump()
    }

    /// Cancels speculative ownership only. Completed decoded and HTTP caches
    /// remain reusable because artwork URLs are content-addressed resources.
    func cancelPrefetches() {
        let ids = scopeStates.values.flatMap(\.demandIDs)
        scopeStates.removeAll()
        for id in ids {
            cancelDemand(id, updateScope: false, shouldPump: false)
        }
        pump()
    }

    // MARK: - Demand ownership

    private func addForegroundDemand(
        id: UUID,
        key: ImageKey,
        continuation: CheckedContinuation<NSImage?, Never>
    ) {
        if let image = images.object(forKey: key.cacheKey) {
            continuation.resume(returning: image)
            return
        }

        nextCreated += 1
        let demand = Demand(
            id: id,
            key: key,
            url: key.url,
            intent: .foreground,
            scope: nil,
            generation: 0,
            batch: 0,
            position: 0,
            created: nextCreated,
            continuation: continuation
        )
        demands[id] = demand
        attachDemand(demand)
        pump()
    }

    private func attachDemand(_ demand: Demand) {
        if let key = demand.key, let decodeJob = decodeJobs[key] {
            decodeJob.consumers.insert(demand.id)
        } else {
            attachToDataJob(demand)
        }
    }

    private func attachToDataJob(_ demand: Demand) {
        let job = dataJobs[demand.url] ?? DataJob(url: demand.url)
        job.consumers.insert(demand.id)
        dataJobs[demand.url] = job
    }

    private func attachToDecodeJob(_ demand: Demand, data: Data) {
        guard let key = demand.key else {
            finishDemand(demand.id, image: nil)
            return
        }
        let job = decodeJobs[key] ?? DecodeJob(key: key, data: data)
        job.consumers.insert(demand.id)
        decodeJobs[key] = job
    }

    private func finishDemand(_ id: UUID, image: NSImage?) {
        guard let demand = demands.removeValue(forKey: id) else { return }
        if let scope = demand.scope,
           var state = scopeStates[scope],
           state.generation == demand.generation {
            state.demandIDs.remove(id)
            scopeStates[scope] = state
        }
        demand.continuation?.resume(returning: image)
        demand.continuation = nil
    }

    private func cancelDemand(
        _ id: UUID,
        updateScope: Bool = true,
        shouldPump: Bool = true
    ) {
        guard let demand = demands.removeValue(forKey: id) else { return }
        if updateScope, let scope = demand.scope,
           var state = scopeStates[scope],
           state.generation == demand.generation {
            state.demandIDs.remove(id)
            scopeStates[scope] = state
        }

        if let dataJob = dataJobs[demand.url] {
            dataJob.consumers.remove(id)
            if dataJob.consumers.isEmpty {
                dataJob.task?.cancel()
                dataJobs.removeValue(forKey: demand.url)
            }
        }
        if let key = demand.key, let decodeJob = decodeJobs[key] {
            decodeJob.consumers.remove(id)
            if decodeJob.consumers.isEmpty, decodeJob.runningID == nil {
                decodeJobs.removeValue(forKey: key)
            }
        }
        demand.continuation?.resume(returning: nil)
        demand.continuation = nil
        if shouldPump { pump() }
    }

    // MARK: - Scheduling

    private func pump() {
        preemptSpeculationForForeground()
        pumpNetwork()
        pumpDecodes()
    }

    private func pumpNetwork() {
        while activeNetworkRequests < policy.maximumNetworkRequests,
              let job = nextPendingDataJob() {
            let runningID = UUID()
            job.runningID = runningID
            activeNetworkRequests += 1
            let loader = dataLoader
            let url = job.url
            job.task = Task { [weak self] in
                let data = await loader.data(for: url)
                self?.dataFinished(url: url, runningID: runningID, data: data)
            }
        }
    }

    private func pumpDecodes() {
        while activeDecodes < policy.maximumDecodes,
              let job = nextPendingDecodeJob() {
            let runningID = UUID()
            job.runningID = runningID
            activeDecodes += 1
            let decoder = decoder
            let key = job.key
            let data = job.data
            job.task = Task { [weak self] in
                let image = await decoder.image(from: data, maxPixelSize: key.pixelSize)
                self?.decodeFinished(key: key, runningID: runningID, image: image)
            }
        }
    }

    private func dataFinished(url: URL, runningID: UUID, data: Data?) {
        activeNetworkRequests -= 1
        guard let job = dataJobs[url], job.runningID == runningID else {
            pump()
            return
        }
        dataJobs.removeValue(forKey: url)
        let consumers = job.consumers.compactMap { demands[$0] }
        if let data {
            for demand in consumers {
                if demand.intent == .cold {
                    finishDemand(demand.id, image: nil)
                } else {
                    attachToDecodeJob(demand, data: data)
                }
            }
        } else {
            for demand in consumers {
                finishDemand(demand.id, image: nil)
            }
        }
        pump()
    }

    private func decodeFinished(key: ImageKey, runningID: UUID, image: NSImage?) {
        activeDecodes -= 1
        guard let job = decodeJobs[key], job.runningID == runningID else {
            pump()
            return
        }
        decodeJobs.removeValue(forKey: key)
        let validConsumers = job.consumers.filter { demands[$0] != nil }
        if let image, !validConsumers.isEmpty {
            images.setObject(
                image,
                forKey: key.cacheKey,
                cost: key.pixelSize * key.pixelSize * 4
            )
        }
        for id in validConsumers {
            finishDemand(id, image: image)
        }
        pump()
    }

    private func nextPendingDataJob() -> DataJob? {
        dataJobs.values
            .filter { $0.runningID == nil && !$0.consumers.isEmpty }
            .max { lhs, rhs in
                jobOutranks(rhs.consumers, lhs.consumers)
            }
    }

    private func nextPendingDecodeJob() -> DecodeJob? {
        decodeJobs.values
            .filter { $0.runningID == nil && !$0.consumers.isEmpty }
            .max { lhs, rhs in
                jobOutranks(rhs.consumers, lhs.consumers)
            }
    }

    private func jobOutranks(_ lhs: Set<UUID>, _ rhs: Set<UUID>) -> Bool {
        guard let left = bestDemand(in: lhs) else { return false }
        guard let right = bestDemand(in: rhs) else { return true }
        return demandOutranks(left, right)
    }

    private func bestDemand(in ids: Set<UUID>) -> Demand? {
        ids.compactMap { demands[$0] }.max { lhs, rhs in
            demandOutranks(rhs, lhs)
        }
    }

    private func demandOutranks(_ lhs: Demand, _ rhs: Demand) -> Bool {
        if lhs.intent != rhs.intent { return lhs.intent.rawValue > rhs.intent.rawValue }
        if lhs.intent == .foreground { return lhs.created < rhs.created }
        if lhs.batch != rhs.batch { return lhs.batch > rhs.batch }
        return lhs.position < rhs.position
    }

    private func preemptSpeculationForForeground() {
        guard activeNetworkRequests >= policy.maximumNetworkRequests,
              dataJobs.values.contains(where: { job in
                  job.runningID == nil && bestDemand(in: job.consumers)?.intent == .foreground
              }),
              let victim = dataJobs.values
                  .filter({ job in
                      job.runningID != nil
                          && bestDemand(in: job.consumers)?.intent != .foreground
                  })
                  .min(by: { lhs, rhs in
                      jobOutranks(rhs.consumers, lhs.consumers)
                  })
        else { return }

        victim.task?.cancel()
        victim.task = nil
        victim.runningID = nil
    }

    private func trimPendingSpeculation(intent: Intent, limit: Int) {
        let pending = demands.values.filter { demand in
            guard demand.intent == intent else { return false }
            if let dataJob = dataJobs[demand.url], dataJob.consumers.contains(demand.id) {
                return dataJob.runningID == nil
            }
            if let key = demand.key,
               let decodeJob = decodeJobs[key],
               decodeJob.consumers.contains(demand.id) {
                return decodeJob.runningID == nil
            }
            return false
        }
        guard pending.count > limit else { return }
        let victims = pending.sorted { lhs, rhs in
            if lhs.batch != rhs.batch { return lhs.batch < rhs.batch }
            return lhs.position > rhs.position
        }.prefix(pending.count - limit)
        for demand in victims {
            cancelDemand(demand.id, shouldPump: false)
        }
    }

    private func prefetchLimits(for scope: PrefetchScope) -> (hot: Int, cold: Int) {
        switch scope {
        case .homeRecentlyPlayed, .homeTopArtists:
            (20, 0)
        case .library:
            (20, 40)
        case .savedAlbums, .followedArtists:
            (30, 100)
        case .queue:
            (30, 0)
        case .detail:
            (24, 76)
        }
    }

    private func prefetchTargetSize(for scope: PrefetchScope) -> CGFloat {
        switch scope {
        case .homeRecentlyPlayed:
            134
        case .homeTopArtists:
            88
        case .library, .savedAlbums, .followedArtists:
            170
        case .queue:
            32
        case .detail:
            112
        }
    }

    private func imageKey(url: URL, targetSize: CGFloat) -> ImageKey {
        ImageKey(url: url, pixelSize: Self.pixelSize(for: targetSize))
    }

    nonisolated private static func pixelSize(for targetSize: CGFloat) -> Int {
        let requested = Int(ceil(targetSize * 2))
        return [64, 160, 320, 640].first(where: { requested <= $0 }) ?? 640
    }

    private static func live() -> ArtworkCache {
        let diskDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Artwork", isDirectory: true)
        let urlCache = URLCache(
            memoryCapacity: 16 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            directory: diskDirectory
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return ArtworkCache(
            dataLoader: URLSessionArtworkDataLoader(configuration: configuration),
            decoder: ImageIOArtworkDecoder()
        )
    }
}

private final class URLSessionArtworkDataLoader: ArtworkDataLoading, @unchecked Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { return nil }
        return data
    }
}

private struct ImageIOArtworkDecoder: ArtworkDecoding {
    func image(from data: Data, maxPixelSize: Int) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else { return nil }
            return NSImage(cgImage: image, size: .zero)
        }.value
    }
}
