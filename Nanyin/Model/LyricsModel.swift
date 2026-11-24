import Foundation
import NanyinKit
import Observation

/// On-demand lyrics loader for the currently playing song.
///
/// Only fetches while the lyrics panel is open:
/// 1. Checks the 30-day local disk cache (`LyricsDiskCache`).
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

        if !force, let cached = cache.load(trackURI: track.uri) {
            switch cached {
            case .found(let lyrics): state = .loaded(lyrics)
            case .notFound: state = .empty
            }
            return
        }

        state = .loading
        let trackID = Route.trackID(track.uri)
        let coverFileID = Self.extractCoverFileID(from: track.coverURL)
        let query = LyricsQuery(
            trackURI: track.uri,
            title: track.name,
            artist: track.artists.first?.name ?? track.artistNames,
            album: track.album,
            durationMs: track.durationMs
        )
        let sessionReady = session.isReady

        loadTask = Task { [weak self] in
            guard let self else { return }
            var spotifyError: Error?
            if sessionReady, let trackID {
                do {
                    if let spotifyLyrics = try await session.readLyrics(trackID: trackID, coverFileID: coverFileID) {
                        guard !Task.isCancelled, self.generation == currentGen else { return }
                        self.cache.save(trackURI: track.uri, lyrics: spotifyLyrics)
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
                    self.cache.save(trackURI: track.uri, lyrics: fallback)
                    self.state = .loaded(fallback)
                    return
                }
                guard !Task.isCancelled, self.generation == currentGen else { return }
                if let spotifyError, !sessionReady {
                    self.state = .failed(spotifyError.localizedDescription)
                } else if spotifyError == nil {
                    // Both Spotify (when connected) and LRCLIB confirmed no lyrics.
                    self.cache.save(trackURI: track.uri, lyrics: nil)
                    self.state = .empty
                } else {
                    // Spotify errored transiently and LRCLIB had no entry: show
                    // empty without caching a miss so Retry can ask Spotify again.
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
        cache.clear()
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

    private static func extractCoverFileID(from url: URL?) -> String? {
        guard let candidate = url?.lastPathComponent,
              !candidate.isEmpty, candidate.count <= 64,
              candidate.allSatisfy(\.isHexDigit)
        else { return nil }
        return candidate
    }
}
