//
//  SavedAlbumsView.swift
//  Nanyin
//

import SwiftUI

/// Saved Albums aggregate page (M4.3): virtualized album rows with cover
/// hover-play, client-side filter, sort orders, and whole-album context
/// playback. Saved albums and Liked Songs are separate concepts — no hearts
/// here, only plus/check semantics.
///
/// Single scroll region: fixed header + one recycling List (UI perf rules).
struct SavedAlbumsView: View {
    @Environment(AppModel.self) private var app

    @State private var filterText = ""
    @State private var sortOrder: SortOrder = .recentlyAdded

    enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently Added"
        case album = "Album"
        case artist = "Artist"
        var id: String { rawValue }
    }

    private var trimmedFilter: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Client-side filter + deterministic sort over the cache display list.
    private var visibleAlbums: [SpotifyClient.SavedAlbum] {
        var list = app.savedAlbums
        if !trimmedFilter.isEmpty {
            list = list.filter {
                $0.album.name.localizedCaseInsensitiveContains(trimmedFilter)
                    || $0.album.artistName.localizedCaseInsensitiveContains(trimmedFilter)
            }
        }
        switch sortOrder {
        case .recentlyAdded:
            break // Display list is already newest-first (server + local inserts).
        case .album:
            list.sort { $0.album.name.localizedStandardCompare($1.album.name) == .orderedAscending }
        case .artist:
            list.sort {
                let byArtist = $0.album.artistName.localizedStandardCompare($1.album.artistName)
                return byArtist == .orderedAscending
                    || (byArtist == .orderedSame
                        && $0.album.name.localizedStandardCompare($1.album.name) == .orderedAscending)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(white: 0.18))
            content
        }
        .background(Theme.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved Albums")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(albumCountLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                filterField
                Spacer()
                sortMenu
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var albumCountLabel: String {
        let count = app.savedAlbumCount
        return count == 1 ? "1 album" : "\(count) albums"
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            TextField("Filter albums…", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(white: 0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(width: 220)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(sortOrder.rawValue)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if let error = app.savedAlbumsError, !app.hasSavedAlbumsData {
            errorState(error)
        } else if !app.hasSavedAlbumsData {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading saved albums…")
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if app.savedAlbums.isEmpty {
            emptyState
        } else if visibleAlbums.isEmpty {
            VStack(spacing: 10) {
                Text("No albums match “\(trimmedFilter)”")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Button("Clear filter") { filterText = "" }
                    .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            albumList
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                app.refreshSavedAlbums(force: true)
            } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text("No saved albums yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("Save albums from any album page — they stay separate from Liked Songs.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                app.focusSearch()
            } label: {
                Text("Search for albums")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Theme.accent)
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var albumList: some View {
        List {
            ForEach(visibleAlbums) { saved in
                SavedAlbumRow(album: saved)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 72)
    }
}

/// One saved-album row: cover with hover play, album/artist/year/count line,
/// saved check (minus on hover = remove). Single click opens the album page.
private struct SavedAlbumRow: View {
    @Environment(AppModel.self) private var app
    let album: SpotifyClient.SavedAlbum

    /// Row-local hover state (never in the list parent — UI perf rules).
    @State private var hovering = false

    private var subtitle: String {
        [
            album.album.artistName,
            album.album.year ?? "",
            album.album.trackCount > 0
                ? (album.album.trackCount == 1 ? "1 track" : "\(album.album.trackCount) tracks")
                : "",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            cover
            VStack(alignment: .leading, spacing: 3) {
                Text(album.album.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            removeButton
                .frame(width: 32, alignment: .center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(hovering ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            app.open(.album(
                id: album.id,
                name: album.album.name,
                subtitle: subtitle,
                artworkURL: album.album.artworkURL
            ))
        }
        .contextMenu {
            Button {
                app.playAlbum(id: album.id)
            } label: {
                Label("Play Album", systemImage: "play")
            }
            Divider()
            Button {
                app.removeSavedAlbum(album)
            } label: {
                Label("Remove from Saved Albums", systemImage: "minus.circle")
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "https://open.spotify.com/album/\(album.id)", forType: .string
                )
            } label: {
                Label("Copy Album Link", systemImage: "link")
            }
        }
        .onHover { hovering = $0 }
    }

    /// Cover with a play affordance on hover — starts the whole album via its
    /// server-resolved context at index 0 (no track-URI upload).
    private var cover: some View {
        ZStack {
            Group {
                if let url = album.album.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(white: 0.14)
                    }
                } else {
                    ZStack {
                        Color(white: 0.14)
                        Image("MusicIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if hovering {
                Color.black.opacity(0.45)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 52, height: 52)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if hovering { app.playAlbum(id: album.id) }
        }
    }

    /// Saved state indicator: check when saved (always, on this page), minus
    /// on hover to communicate removal.
    private var removeButton: some View {
        Button {
            app.removeSavedAlbum(album)
        } label: {
            Image(systemName: hovering ? "minus.circle" : "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(hovering ? Theme.textSecondary : Theme.accent)
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.85)
        .help("Remove from Saved Albums")
    }
}
