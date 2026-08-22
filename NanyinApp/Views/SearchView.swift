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
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool

    private var query: String {
        app.searchQuery
    }

    private var results: [SpotifyClient.Track] {
        app.tracksByContext["search"] ?? []
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The old M0 home "paste a track URI" box lives on here: a pasted track
    /// link/URL switches the page to a direct play affordance instead of a
    /// text search. Accepts locale-prefixed URLs
    /// (open.spotify.com/intl-zh/track/…) — same tail-id rule as trackId(from:).
    static func pastedTrackLinkID(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("spotify:track:") || t.contains("/track/") else { return nil }
        return SpotifyClient.trackId(from: t)
    }

    var body: some View {
        VStack(spacing: 0) {
            if theme.id != .classic2010 {
                searchField
                Divider().overlay(theme.colors.divider)
            }
            content
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
        .onAppear {
            if theme.id != .classic2010 {
                focused = true
            }
        }
        .onChange(of: app.searchFocusToken) {
            if theme.id != .classic2010 {
                focused = true
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.colors.secondaryText)
            TextField(
                "Search for songs or artists",
                text: Binding(
                    get: { app.searchQuery },
                    set: { value in
                        app.searchQuery = value
                        if Self.pastedTrackLinkID(value) == nil {
                            app.searchDebounced(value)
                        }
                    }
                )
            )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit {
                    if Self.pastedTrackLinkID(query) == nil {
                        app.search(query)
                    }
                }
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
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.metrics.fieldHorizontalPadding)
        .padding(.vertical, theme.metrics.fieldVerticalPadding)
        .background(theme.colors.inputBackground.swiftUIStyle)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius)
                .strokeBorder(
                    focused ? theme.colors.focusRing : theme.colors.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadius))
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset)
        .padding(.bottom, theme.metrics.pageBottomInset)
    }

    private func clearQuery() {
        app.searchQuery = ""
        app.search("")
        focused = true
    }

    // MARK: - Results

    @ViewBuilder
    private var content: some View {
        if Self.pastedTrackLinkID(query) != nil {
            linkPlayCard
        } else if let error = app.tracksError["search"] {
            messageState(
                icon: Image(systemName: "exclamationmark.triangle"),
                text: error,
                tint: theme.colors.error,
                isError: true
            )
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
                        .foregroundStyle(theme.colors.secondaryText)
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
                .font(theme.typography.sectionLabel)
            Text("\(results.count) results")
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.sectionTopPadding + 2)
        .padding(.bottom, theme.metrics.sectionBottomPadding)
    }

    /// Direct play affordance for a pasted track link (URI box successor).
    private var linkPlayCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.colors.secondaryText)
            Text("Track Link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("Paste any Spotify track link or URI (https://open.spotify.com/track/… or spotify:track:…) and play it directly.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                app.playURI(query)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("PLAY")
                        .font(theme.typography.button)
                        .tracking(0.8)
                }
                .foregroundStyle(theme.colors.inverseText)
                .padding(.horizontal, theme.metrics.controlHorizontalPadding)
                .padding(.vertical, theme.metrics.controlVerticalPadding)
                .background(
                    app.isPlaybackReady
                        ? AnyShapeStyle(theme.colors.accent)
                        : theme.colors.disabledSurface.swiftUIStyle
                )
                .cornerRadius(theme.metrics.pillCornerRadius)
            }
            .buttonStyle(.plain)
            .disabled(!app.isPlaybackReady)
            .padding(.top, 2)
            if let note = app.connectionNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageState(
        icon: Image,
        text: String,
        subtext: String? = nil,
        tint: Color? = nil,
        isError: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .foregroundStyle(tint ?? theme.colors.secondaryText)
            Text(text)
                .font(theme.typography.messageTitle)
                .foregroundStyle(theme.colors.secondaryText)
            if let subtext {
                Text(subtext)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isError
                ? theme.colors.errorContainer.swiftUIStyle
                : AnyShapeStyle(Color.clear)
        )
        .overlay {
            if isError {
                RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius)
                    .strokeBorder(theme.colors.errorBorder, lineWidth: 1)
            }
        }
    }
    // MARK: - Artists

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists")
                .font(theme.typography.sectionLabel)
                .padding(.horizontal, theme.metrics.pageHorizontalInset)
            // Horizontal strip above the vertical List — perpendicular axes,
            // so the single-scroll-region rule (no same-axis nesting) holds.
            // Capped at 10: the row is not lazy; every card mounts immediately.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.metrics.smallPadding + 4) {
                    ForEach(app.searchArtists.prefix(10)) { artist in
                        ArtistCard(artist: artist)
                    }
                }
                .padding(.horizontal, theme.metrics.pageHorizontalInset)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, theme.metrics.sectionTopPadding + 2)
        .padding(.bottom, theme.metrics.sectionBottomPadding - 2)
    }
}

/// Circular-portrait artist card. Hover state is card-local (same rule as
/// track rows — never in the list parent).
private struct ArtistCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let artist: SpotifyClient.Artist

    @State private var hovering = false

    private var artworkSize: CGFloat { theme.metrics.artistArtworkSize }

    var body: some View {
        Button {
            app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
        } label: {
            VStack(spacing: 8) {
                portrait
                Text(artist.name)
                    .font(theme.typography.tileTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Artist")
                    .font(theme.typography.tileSubtitle)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(width: artworkSize + theme.metrics.smallPadding * 2)
            .padding(theme.metrics.smallPadding)
            .background(
                hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear)
            )
            .cornerRadius(theme.metrics.cardCornerRadius)
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
        ArtworkView(url: artist.artworkURL, size: artworkSize) {
            placeholderPortrait
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(Circle())
        .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
    }

    private var placeholderPortrait: some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: artworkSize * 0.45))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
