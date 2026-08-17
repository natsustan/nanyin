//
//  AppModel.swift
//  Nanyin
//

import Foundation
import Observation

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

    // MARK: - Auth

    private(set) var authState: AuthState = .checking
    private(set) var userDisplayName: String = ""
    private(set) var authError: String?

    private var accessToken: String = ""
    private var tokenExpiry: Date = .distantPast
    private var api: SpotifyClient?

    // MARK: - Playback

    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var positionMs: UInt32 = 0
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

    private var positionTimer: Timer?

    // MARK: - Lifecycle

    init() {
        installCoreCallbacks()
    }

    func start() {
        Task {
            do {
                let token = try await SpotifyAuth.refreshAccessToken()
                apply(token: token)
                try await initPlayerAndUser()
                authState = .loggedIn
            } catch {
                authState = .loggedOut
            }
        }
    }

    func signIn() {
        authState = .signingIn
        authError = nil
        Task {
            do {
                let token = try await SpotifyAuth.signIn()
                apply(token: token)
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
        SpotifyAuth.storedRefreshToken = nil
        accessToken = ""
        api = nil
        nowPlaying = nil
        authState = .loggedOut
    }

    private func apply(token: SpotifyAuth.Token) {
        accessToken = token.accessToken
        tokenExpiry = token.expiresAt
        api = SpotifyClient(accessToken: token.accessToken)
    }

    private func initPlayerAndUser() async throws {
        let rc = Core.initializePlayer(accessToken: accessToken)
        guard rc == 0 else {
            throw SpotifyClient.APIError.http(Int(rc), "player init failed")
        }
        if let profile = try? await api?.currentUser() {
            userDisplayName = profile.displayName ?? profile.id
        }
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
        case let .playing(_, positionMs):
            isPlaying = true
            isBuffering = false
            self.positionMs = UInt32(positionMs)
        case let .paused(_, positionMs):
            isPlaying = false
            self.positionMs = UInt32(positionMs)
        case .stopped:
            isPlaying = false
            isBuffering = false
        case let .loading(uri, _):
            isBuffering = true
            fetchMetadata(uri: uri)
        case let .trackChanged(uri, durationMs):
            self.durationMs = UInt32(durationMs)
            fetchMetadata(uri: uri)
        case let .position(positionMs):
            self.positionMs = UInt32(positionMs)
        case .endOfTrack:
            break // M2: auto-advance handling; Spirc usually advances itself
        }
    }

    private func fetchMetadata(uri: String) {
        guard let id = SpotifyClient.trackId(from: uri) else { return }
        // Update immediately from URI form; enrich via Web API.
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

    /// Session dropped: silently refresh the token and re-init the player
    /// (cliamp lesson: never auto-open a browser from the error path).
    private func reconnect() {
        connectionNote = "Reconnecting…"
        Task {
            do {
                let token = try await SpotifyAuth.refreshAccessToken()
                apply(token: token)
                let rc = Core.initializePlayer(accessToken: accessToken)
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
        if SpotifyClient.trackId(from: uri) != nil, !uri.hasPrefix("spotify:") {
            // Convert URL form to URI form.
            if let id = SpotifyClient.trackId(from: uri) {
                uri = "spotify:track:\(id)"
            }
        }
        _ = Core.playTracks([uri])
    }

    func togglePlay() {
        if isPlaying {
            _ = Core.pause()
        } else {
            _ = Core.resume()
        }
    }

    func seek(to fraction: Double) {
        let target = UInt32(fraction * Double(max(durationMs, 1)))
        _ = Core.seek(target)
        positionMs = target
    }

    func setVolume(_ fraction: Double) {
        volume = fraction
        AudioRenderer.shared.volume = Float(fraction)
        _ = Core.setVolume(UInt16(fraction * 65_535))
    }

    func next() { _ = Core.next() }
    func prev() { _ = Core.prev() }

    // MARK: - Position polling

    func startPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.positionMs = Core.positionMs
            }
        }
    }
}
