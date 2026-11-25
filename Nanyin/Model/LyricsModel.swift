import Foundation
import NanyinKit
import Observation

/// On-demand lyrics loader for the currently playing song.
///
/// Only fetches while the lyrics panel is open:
/// 1. Checks the 30-day local disk cache (`LyricsDiskCache`) off the main thread.
/// 2. Queries Spotify's `color-lyrics` endpoint over the active playback session.
/// 3. Falls back to [LRCLIB](https://lrclib.net) when Spotify has no lyrics.
@MainActor
@Observable
final class LyricsModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case empty
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var trackURI: String?

    private let session: PlaybackSession
    private let lrclib: LRCLIBClient
    private let cache: LyricsDiskCache
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(session: PlaybackSession, transport: HTTPTransport, bundleID: String) {
        self.session = session
        self.lrclib = LRCLIBClient(transport: transport)
        self.cache = LyricsDiskCache(directory: LyricsDiskCache.defaultDirectory(bundleID: bundleID))
    }

    func load(for track: CoreTrack?, force: Bool = false) {
        guard let track else {
            cancel()
            trackURI = nil
            state = .idle
            return
        }
        if !force, track.uri == trackURI, state != .idle {
            return
        }

        loadTask?.cancel()
        generation += 1
        let currentGen = generation
        trackURI = track.uri
        state = .loading

        let spotifyURI = track.linkedURI ?? track.uri
        let trackID = Route.trackID(spotifyURI)
        let coverFileID = track.linkedURI == nil ? Self.extractCoverFileID(from: track.coverURL) : nil
        let query = LyricsQuery(
            trackURI: track.uri,
            title: track.name,
            artist: track.artists.first?.name ?? track.artistNames,
            album: track.album,
            durationMs: track.durationMs
        )
        let sessionReady = session.isReady
        let cache = self.cache

        loadTask = Task { [weak self] in
            if !force {
                let cached = await Task.detached(priority: .utility) {
                    cache.load(trackURI: track.uri)
                }.value
                guard !Task.isCancelled, let self, self.generation == currentGen else { return }
                if let cached {
                    switch cached {
                    case .found(let lyrics): self.state = .loaded(lyrics)
                    case .notFound: self.state = .empty
                    }
                    return
                }
            }

            guard let self else { return }
            let queriedSpotify = sessionReady && trackID != nil
            var spotifyError: Error?
            if queriedSpotify, let trackID {
                do {
                    if let spotifyLyrics = try await session.readLyrics(trackID: trackID, coverFileID: coverFileID) {
                        guard !Task.isCancelled, self.generation == currentGen else { return }
                        Self.saveInBackground(cache: cache, trackURI: track.uri, lyrics: spotifyLyrics)
                        self.state = .loaded(spotifyLyrics)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    spotifyError = error
                }
            }

            do {
                if let fallback = try await lrclib.fetch(query) {
                    guard !Task.isCancelled, self.generation == currentGen else { return }
                    Self.saveInBackground(cache: cache, trackURI: track.uri, lyrics: fallback)
                    self.state = .loaded(fallback)
                    return
                }
                guard !Task.isCancelled, self.generation == currentGen else { return }
                if let spotifyError {
                    // Spotify errored transiently and LRCLIB had no entry: surface the error without caching a miss.
                    self.state = .failed(spotifyError.localizedDescription)
                } else if queriedSpotify {
                    // Both Spotify and LRCLIB confirmed no lyrics.
                    Self.saveInBackground(cache: cache, trackURI: track.uri, lyrics: nil)
                    self.state = .empty
                } else {
                    // Playback session was not connected yet, so don't cache a 24h miss.
                    self.state = .empty
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.generation == currentGen else { return }
                self.state = .failed((spotifyError ?? error).localizedDescription)
            }
        }
    }

    func clearCache() {
        let cache = self.cache
        Task.detached(priority: .utility) {
            cache.clear()
        }
    }

    func reset() {
        cancel()
        trackURI = nil
        state = .idle
    }

    private func cancel() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
    }

    private static func saveInBackground(cache: LyricsDiskCache, trackURI: String, lyrics: Lyrics?) {
        Task.detached(priority: .utility) {
            cache.save(trackURI: trackURI, lyrics: lyrics)
        }
    }

    private static func extractCoverFileID(from url: URL?) -> String? {
        guard let candidate = url?.lastPathComponent,
              !candidate.isEmpty, candidate.count <= 64,
              candidate.allSatisfy(\.isHexDigit)
        else { return nil }
        return candidate
    }
}
