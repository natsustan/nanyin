//
//  HomeView.swift
//  Nanyin
//

import SwiftUI

/// M0 smoke-test screen: paste any track URI/URL and play it.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var trackInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Home")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                if let user = app.userDisplayName.isEmpty ? nil : app.userDisplayName {
                    Text("Signed in as \(user)")
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("PLAY A TRACK")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Theme.textSecondary)

                    Text("Paste a Spotify track link or URI (e.g. https://open.spotify.com/track/… or spotify:track:…)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))

                    HStack(spacing: 12) {
                        TextField("https://open.spotify.com/track/…", text: $trackInput)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color(white: 0.16))
                            .cornerRadius(6)
                            .foregroundStyle(.white)
                            .onSubmit(play)

                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(10)
                                .background(canPlay ? Theme.accent : Theme.accent.opacity(0.4))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canPlay)
                    }

                    HStack(spacing: 8) {
                        if app.isBuffering {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let note = app.connectionNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(20)
                .background(Color(white: 0.09))
                .cornerRadius(8)

                Text("M1 preview: playlists and Liked Songs will appear here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(32)
        }
        .background(Theme.background)
    }

    private var canPlay: Bool {
        app.isPlaybackReady && SpotifyClient.trackId(from: trackInput) != nil
    }

    private func play() {
        guard canPlay else { return }
        app.playURI(trackInput)
    }
}
