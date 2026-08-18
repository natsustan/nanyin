//
//  PlaylistDetailView.swift
//  Nanyin
//

import SwiftUI

/// Header (cover + name + count + play button) + track list.
/// Used for playlists and Liked Songs.
struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var app

    let title: String
    let subtitle: String
    let coverURL: URL?
    let contextKey: String
    /// Header eyebrow: PLAYLIST / ALBUM / …
    var label = "PLAYLIST"

    private var tracks: [SpotifyClient.Track] {
        app.tracksByContext[contextKey] ?? []
    }

    var body: some View {
        Group {
            if let error = app.tracksError[contextKey] {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 12) {
                    if app.loadingTracks {
                        ProgressView()
                        Text("Loading tracks…")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Nothing here yet")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Single scroll region: fixed header + recycling List (the List
                // inside TrackListView is the ONLY scroller on this page —
                // the previous nested-ScrollView layout caused scroll jank).
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Color(white: 0.18))
                    TrackListView(tracks: tracks, contextKey: contextKey)
                }
            }
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 24) {
            cover
                .frame(width: 140, height: 140)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    if let first = tracks.first {
                        app.play(track: first, contextKey: contextKey)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("PLAY")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Theme.accent)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Theme.background)
    }

    @ViewBuilder
    private var cover: some View {
        if let url = coverURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholderCover
            }
        } else {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
