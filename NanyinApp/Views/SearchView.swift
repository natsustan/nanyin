//
//  SearchView.swift
//  Nanyin
//

import SwiftUI

/// Search page (M3): debounced-as-you-type search over /v1/search
/// (tracks + artists). Tracks render in the shared TrackListView and play as
/// an ad-hoc windowed context ("search" key → nanyin_play_tracks — results
/// are small). Artists render as a horizontal card row → artist page.
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
            TextField("Search for songs or artists", text: $query)
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
            messageState(icon: Image(systemName: "exclamationmark.triangle"), text: error, tint: .orange)
        } else if trimmedQuery.isEmpty {
            messageState(
                icon: Image(systemName: "magnifyingglass"),
                text: "Search Spotify",
                subtext: "Find songs and artists — press ⌘K from anywhere"
            )
        } else if results.isEmpty && app.searchArtists.isEmpty {
            if app.isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageState(icon: Image("MusicIcon"), text: "No results for “\(trimmedQuery)”")
            }
        } else {
            // Single scroll region: fixed headers + the List inside
            // TrackListView is the ONLY vertical scroller on this page.
            VStack(spacing: 0) {
                if !app.searchArtists.isEmpty {
                    artistsSection
                }
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
        icon: Image,
        text: String,
        subtext: String? = nil,
        tint: Color = Theme.textSecondary
    ) -> some View {
        VStack(spacing: 10) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
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
    // MARK: - Artists

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists")
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 28)
            // Horizontal strip above the vertical List — perpendicular axes,
            // so the single-scroll-region rule (no same-axis nesting) holds.
            // Capped at 10: the row is not lazy; every AsyncImage would fire.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.searchArtists.prefix(10)) { artist in
                        ArtistCard(artist: artist)
                    }
                }
                .padding(.horizontal, 28)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// Circular-portrait artist card. Hover state is card-local (same rule as
/// track rows — never in the list parent).
private struct ArtistCard: View {
    @Environment(AppModel.self) private var app
    let artist: SpotifyClient.Artist

    @State private var hovering = false

    var body: some View {
        Button {
            app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
        } label: {
            VStack(spacing: 8) {
                portrait
                Text(artist.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Artist")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 104)
            .padding(8)
            .background(hovering ? Color(white: 0.13) : .clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hovering = hovering
        }
        .linkCursor()
    }

    @ViewBuilder
    private var portrait: some View {
        Group {
            if let url = artist.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderPortrait
                }
            } else {
                placeholderPortrait
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private var placeholderPortrait: some View {
        ZStack {
            Color(white: 0.14)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
