//
//  AppModel.swift
//  Nanyin
//

import Foundation
import Observation

/// Unbuffered debug logging to stderr (survives process kill, unlike print).
func dlog(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data("[nanyin] \(message())\n".utf8))
}

/// App-wide state: auth, playback, and glue between Web API and the Rust core.
@Observable
@MainActor
final class AppModel {
    enum AuthState {
        case checking // trying silent refresh on launch
        case loggedOut
        case signingIn
        case loggedIn
    }

    struct PlayerInitError: Error, LocalizedError {
        let message: String
        init(detail: String) { message = detail }
        var errorDescription: String? { message }
    }

    // MARK: - Auth

    private(set) var authState: AuthState = .checking
    private(set) var userDisplayName: String = ""
    private(set) var authError: String?

    private var playbackAccessToken: String = ""
    private var webAccessToken: String = ""
    private var api: SpotifyClient?

    // MARK: - Playback

    private(set) var isPlaying = false
    private(set) var isBuffering = false
    // NOTE: playback position is intentionally NOT stored here. Polling it at
    // 2Hz from the app-wide observable would invalidate every view reading
    // the model (including every track row) — PlayerBar ticks it locally.
    private(set) var durationMs: UInt32 = 0
    private(set) var volume: Double = 1.0 // 0…1

    struct NowPlaying {
        let uri: String
        let title: String
        let artist: String
        let album: String
        let artworkURL: URL?
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var connectionNote: String?

    // MARK: - Library (M1)

    enum Page: Hashable {
        case home
        case liked
        case playlist(id: String, name: String)

        var contextKey: String? {
            switch self {
            case .home: nil
            case .liked: "liked"
            case let .playlist(id, _): id
            }
        }
    }

    private(set) var page: Page = .home
    private(set) var playlists: [SpotifyClient.PlaylistInfo] = []
    private(set) var likedCount = 0
    private(set) var tracksByContext: [String: [SpotifyClient.Track]] = [:]
    private(set) var loadingTracks = false
    private(set) var tracksError: [String: String] = [:]


    // MARK: - Lifecycle

    init() {
        installCoreCallbacks()
    }

    func start() {
        Task {
            do {
                dlog("silent refresh…")
                let web = try await SpotifyAuth.refreshAccessToken(for: .web)
                apply(webToken: web)
                dlog("web refresh OK, playback refresh…")
                let playback = try await SpotifyAuth.refreshAccessToken(for: .playback)
                apply(playbackToken: playback)
                dlog("refresh OK, init player…")
                try await initPlayerAndUser()
                authState = .loggedIn
                dlog("logged in (silent)")
            } catch {
                dlog("silent login failed: \(error)")
                authState = .loggedOut
            }
        }
    }

    func signIn() {
        authState = .signingIn
        authError = nil
        Task {
            do {
                let tokens = try await SpotifyAuth.signIn()
                apply(webToken: tokens.web)
                apply(playbackToken: tokens.playback)
                try await initPlayerAndUser()
                authState = .loggedIn
            } catch {
                authError = error.localizedDescription
                authState = .loggedOut
            }
        }
    }

    func signOut() {
        Core.stop()
        AudioRenderer.shared.stop()
        SpotifyAuth.setRefreshToken(nil, for: .web)
        SpotifyAuth.setRefreshToken(nil, for: .playback)
        playbackAccessToken = ""
        webAccessToken = ""
        api = nil
        nowPlaying = nil
        authState = .loggedOut
    }

    private func apply(webToken: SpotifyAuth.Token) {
        webAccessToken = webToken.accessToken
        api = SpotifyClient(accessToken: webToken.accessToken)
    }

    private func apply(playbackToken: SpotifyAuth.Token) {
        playbackAccessToken = playbackToken.accessToken
    }

    private func initPlayerAndUser() async throws {
        let rc = Core.initializePlayer(accessToken: playbackAccessToken)
        guard rc == 0 else {
            let detail = Core.lastErrorMessage() ?? "unknown"
            dlog("player init rc=\(rc): \(detail)")
            throw PlayerInitError(detail: "Player init failed (rc \(rc)): \(detail)")
        }
        do {
            if let profile = try await api?.currentUser() {
                userDisplayName = profile.displayName ?? profile.id
                dlog("/v1/me OK — \(userDisplayName)")
            }
        } catch {
            dlog("/v1/me failed: \(error)")
        }
        loadLibrary()
    }

    /// Loads playlists + liked songs in the background after login.
    private func loadLibrary() {
        Task {
            do {
                let lists = try await api!.playlists()
                playlists = lists
                likedCount = try await api!.likedTotal()
                // Warm the liked-songs cache; it powers the most common entry point.
                if tracksByContext["liked"] == nil {
                    tracksByContext["liked"] = try? await api!.likedTracks()
                }
            } catch {
                dlog("library load failed: \(error)")
            }
        }
    }

    // MARK: - Navigation

    func open(_ newPage: Page) {
        page = newPage
        guard let key = newPage.contextKey, tracksByContext[key] == nil else { return }
        loadingTracks = true
        tracksError[key] = nil
        Task {
            do {
                let tracks: [SpotifyClient.Track]
                switch newPage {
                case .liked:
                    tracks = try await api!.likedTracks()
                case let .playlist(id, _):
                    tracks = try await api!.playlistTracks(id)
                case .home:
                    loadingTracks = false
                    return
                }
                tracksByContext[key] = tracks
            } catch {
                tracksError[key] = error.localizedDescription
                dlog("tracks load failed: \(error)")
            }
            loadingTracks = false
        }
    }

    /// Plays a track within its loaded context (playlist / liked),
    /// continuing with the rest of the context afterwards.
    func play(track: SpotifyClient.Track, contextKey: String) {
        let uris: [String]
        let startIndex: Int
        if let context = tracksByContext[contextKey],
           let index = context.firstIndex(where: { $0.uri == track.uri })
        {
            uris = context.map(\.uri)
            startIndex = index
        } else {
            uris = [track.uri]
            startIndex = 0
        }
        applyNowPlaying(track)
        isBuffering = true
        let rc = Core.playTracks(uris, startIndex: startIndex)
        dlog("playTracks(\(uris.count) uris, index \(startIndex)) rc=\(rc)")
    }

    // MARK: - Core callbacks

    private func installCoreCallbacks() {
        Core.onAudioData = { samples, count in
            AudioRenderer.shared.write(samples: samples, count: count)
        }
        Core.onAudioControl = { event in
            switch event {
            case 0: AudioRenderer.shared.stop()      // AUDIO_CONTROL_STOP
            case 1: AudioRenderer.shared.start()     // AUDIO_CONTROL_START
            case 2: AudioRenderer.shared.clear()     // AUDIO_CONTROL_CLEAR
            default: break
            }
        }
        Core.onConnected = {
            self.connectionNote = nil
        }
        Core.onDisconnected = {
            self.reconnect()
        }
        Core.onEvent = { event in
            self.handle(event)
        }
    }

    private func handle(_ event: Core.Event) {
        switch event {
        case .playing:
            isPlaying = true
            isBuffering = false
        case let .paused(_, positionMs):
            isPlaying = false
            // Rare low-frequency update; PlayerBar interpolates via Core polling.
            _ = positionMs
        case .stopped:
            isPlaying = false
            isBuffering = false
        case let .loading(uri, _):
            isBuffering = true
            fetchMetadata(uri: uri)
        case let .trackChanged(uri, durationMs):
            self.durationMs = UInt32(durationMs)
            fetchMetadata(uri: uri)
        case .position:
            break // position handled by PlayerBar's local Core.positionMs polling
        case .endOfTrack:
            break // M2: auto-advance handling; Spirc usually advances itself
        }
    }

    private func fetchMetadata(uri: String) {
        // Skip when we already have richer local data for this URI.
        if nowPlaying?.uri == uri, nowPlaying?.title != "…" { return }
        guard let id = SpotifyClient.trackId(from: uri) else { return }
        if nowPlaying?.uri != uri {
            nowPlaying = NowPlaying(uri: uri, title: "…", artist: "", album: "", artworkURL: nil)
        }
        Task {
            guard let track = try? await api?.track(id: id) else { return }
            let artwork = track.artworkURL
            nowPlaying = NowPlaying(
                uri: uri,
                title: track.name,
                artist: track.artists.joined(separator: ", "),
                album: track.albumName,
                artworkURL: artwork
            )
        }
    }

    private func applyNowPlaying(_ track: SpotifyClient.Track) {
        nowPlaying = NowPlaying(
            uri: track.uri,
            title: track.name,
            artist: track.artists.joined(separator: ", "),
            album: track.albumName,
            artworkURL: track.artworkURL
        )
    }

    /// Session dropped: silently refresh the token and re-init the player
    /// (cliamp lesson: never auto-open a browser from the error path).
    private func reconnect() {
        connectionNote = "Reconnecting…"
        Task {
            do {
                let token = try await SpotifyAuth.refreshAccessToken(for: .playback)
                apply(playbackToken: token)
                let rc = Core.initializePlayer(accessToken: playbackAccessToken)
                if rc == 0 {
                    connectionNote = nil
                } else {
                    connectionNote = "Connection lost"
                }
            } catch {
                connectionNote = "Connection lost — sign in again"
            }
        }
    }

    // MARK: - Playback commands

    func playURI(_ input: String) {
        var uri = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uri.hasPrefix("spotify:"), let id = SpotifyClient.trackId(from: uri) {
            uri = "spotify:track:\(id)"
        }
        dlog("playURI → \(uri)")
        let rc = Core.playTracks([uri])
        dlog("playTracks rc=\(rc)")
        if rc == 0 {
            isBuffering = true
        }
    }

    func togglePlay() {
        if isPlaying {
            _ = Core.pause()
        } else {
            _ = Core.resume()
        }
    }

    func seek(to fraction: Double) {
        _ = Core.seek(UInt32(fraction * Double(max(durationMs, 1))))
    }

    func setVolume(_ fraction: Double) {
        volume = fraction
        AudioRenderer.shared.volume = Float(fraction)
        _ = Core.setVolume(UInt16(fraction * 65_535))
    }

    func next() { _ = Core.next() }
    func prev() { _ = Core.prev() }

}
