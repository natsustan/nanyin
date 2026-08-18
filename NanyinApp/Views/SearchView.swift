//
//  SearchView.swift
//  Nanyin
//

import SwiftUI

/// Search page (M3): debounced-as-you-type track search over /v1/search.
/// Results render in the shared TrackListView and play as an ad-hoc
/// windowed context ("search" key → nanyin_play_tracks — results are small).
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [SpotifyClient.Track] {
        app.tracksByContext["search"] ?? []
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Color(white: 0.18))
            content
        }
        .background(Theme.background)
        .onAppear {
            // Restore across page switches (view is destroyed by RootView's
            // switch; the model keeps query + cached results in sync).
            if query.isEmpty { query = app.searchQuery }
            focused = true
        }
        .onChange(of: app.searchFocusToken) { focused = true }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Search for songs", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit { app.search(query) }
                .onKeyPress(.escape) {
                    if query.isEmpty {
                        focused = false
                    } else {
                        clearQuery()
                    }
                    return .handled
                }
            if app.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button(action: clearQuery) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(white: 0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(focused ? Theme.accent : Color(white: 0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .onChange(of: query) { _, new in
            app.searchQuery = new
            app.searchDebounced(new)
        }
    }

    private func clearQuery() {
        query = ""
        app.search("")
        focused = true
    }

    // MARK: - Results

    @ViewBuilder
    private var content: some View {
        if let error = app.tracksError["search"] {
            messageState(icon: "exclamationmark.triangle", text: error, tint: .orange)
        } else if trimmedQuery.isEmpty {
            messageState(
                icon: "magnifyingglass",
                text: "Search Spotify",
                subtext: "Find your favorite songs — press ⌘K from anywhere"
            )
        } else if results.isEmpty {
            if app.isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageState(icon: "music.quarternote.3", text: "No songs found for “\(trimmedQuery)”")
            }
        } else {
            // Single scroll region: fixed header + the List inside
            // TrackListView is the ONLY scroller on this page.
            VStack(spacing: 0) {
                resultsHeader
                TrackListView(tracks: results, contextKey: "search")
            }
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 10) {
            Text("Songs")
                .font(.system(size: 14, weight: .bold))
            Text("\(results.count) results")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func messageState(
        icon: String,
        text: String,
        subtext: String? = nil,
        tint: Color = Theme.textSecondary
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let subtext {
                Text(subtext)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
