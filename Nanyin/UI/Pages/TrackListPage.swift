import NanyinKit
import SwiftUI

/// Shared filterable/sortable track-list body with Play, Shuffle, Filter, and
/// Sort controls, used by both `PlaylistPage` and `StarredPage`.
struct FilterableTrackList<ExtraControls: View>: View {
    @Environment(AppModel.self) private var app
    let list: TrackList
    let contextURI: String?
    var columns = TrackTable.Column.standard
    var editablePlaylist: Playlist? = nil
    var allowReorder = false
    @ViewBuilder var extraControls: () -> ExtraControls

    @State private var filter = ""
    @State private var activeFilter = ""
    @State private var filterDebounce: Task<Void, Never>?
    @State private var autoPagesFetched = 0
    @State private var reachedFilteredEnd = false
    @State private var sort: PlaylistSort = .custom
    @State private var sortAscending = true

    /// Caps automatic page fetches per filter session so a non-matching query
    /// on a huge library cannot fire an unbounded burst of Web API calls.
    private static var maxAutoFilterPages: Int { 8 }

    var body: some View {
        let pages = list.pages
        let displayed = displayedRows
        let canAutoFetchMore = !activeFilter.isEmpty && pages.hasMore
            && autoPagesFetched < Self.maxAutoFilterPages
            && (displayed.count < 20 || reachedFilteredEnd)

        VStack(spacing: 0) {
            actionBar(displayed: displayed)
            if !activeFilter.isEmpty && displayed.isEmpty {
                if canAutoFetchMore {
                    PlaceholderText(
                        message: pages.error ?? "Searching more tracks…",
                        retry: pages.error != nil ? { pages.retry() } : nil
                    )
                } else if pages.hasMore {
                    PlaceholderText(
                        message: "No matches in the first \(list.rows.count) tracks.",
                        retry: {
                            autoPagesFetched = 0
                            pages.loadNext()
                        }
                    )
                } else {
                    PlaceholderText(message: "No matching tracks.")
                }
            } else {
                TrackListTable(
                    list: list,
                    columns: columns,
                    rowsOverride: isCustomView ? displayed : nil,
                    playOverride: playDisplayed ? { row in
                        app.player.play(rows: displayed, start: row, contextURI: contextURI)
                    } : nil,
                    onRowAppeared: isCustomView ? { index in
                        if index >= displayed.count - 20 {
                            if !activeFilter.isEmpty { reachedFilteredEnd = true }
                            list.pages.loadNext()
                        }
                    } : nil,
                    editablePlaylist: editablePlaylist,
                    onReorder: (allowReorder && !isCustomView && editablePlaylist != nil) ? { from, insertBefore, uri in
                        if let editablePlaylist {
                            app.library.reorderTrack(from: from, insertBefore: insertBefore, uri: uri, in: editablePlaylist, list: list)
                        }
                    } : nil
                )
            }
        }
        .task(id: canAutoFetchMore ? "\(activeFilter)|\(pages.items.count)" : "") {
            guard canAutoFetchMore else { return }
            autoPagesFetched += 1
            pages.loadNext()
        }
        .onChange(of: filter) { _, raw in
            filterDebounce?.cancel()
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                activeFilter = ""
                autoPagesFetched = 0
                reachedFilteredEnd = false
                return
            }
            filterDebounce = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                activeFilter = trimmed
                autoPagesFetched = 0
                reachedFilteredEnd = false
            }
        }
        .onChange(of: displayed.count) { reachedFilteredEnd = false }
    }

    private func actionBar(displayed: [TrackRow]) -> some View {
        let player = app.player
        let controlsCurrent = contextURI != nil && !isCustomView && player.contextURI == contextURI && player.track != nil
        let isPlayingHere = controlsCurrent && player.isPlaying
        let canPlay = playDisplayed ? !displayed.isEmpty : (!list.rows.isEmpty || (list.pages.total ?? 1) > 0)

        return HStack(spacing: 8) {
            Button {
                if controlsCurrent {
                    player.togglePlayPause()
                } else if playDisplayed {
                    player.play(rows: displayed, contextURI: contextURI)
                } else if let contextURI {
                    player.play(contextURI: contextURI)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isPlayingHere ? "pause.fill" : "play.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(isPlayingHere ? "Pause" : "Play")
                }
            }
            .buttonStyle(GraphiteActionButtonStyle())
            .disabled(contextURI == nil || (!controlsCurrent && !canPlay))

            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
            }
            .buttonStyle(GraphiteToggleStyle(isOn: player.shuffle))
            .help(player.shuffle ? "Turn Shuffle Off" : "Turn Shuffle On")

            extraControls()

            Spacer(minLength: 8)

            DarkFilterField(text: $filter, prompt: "Filter")
                .frame(width: 170)

            sortMenu
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.graphite)
        .hairline(.top, Theme.graphiteHighlight)
        .hairline(.bottom, Theme.graphiteEdge)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PlaylistSort.allCases, id: \.self) { option in
                Button {
                    if sort == option {
                        if option != .custom { sortAscending.toggle() }
                    } else {
                        sort = option
                        sortAscending = option.defaultAscending
                    }
                } label: {
                    Text(sort == option ? "✓ \(option.buttonLabel(ascending: sortAscending))" : option.label)
                }
            }
        } label: {
            Text(sort.buttonLabel(ascending: sortAscending))
                .font(AquaFont.bold(11))
        }
        .menuStyle(.button)
        .buttonStyle(GraphiteActionButtonStyle())
        .fixedSize()
    }

    private var isCustomView: Bool {
        !activeFilter.isEmpty || sort != .custom
    }

    private var playDisplayed: Bool {
        !activeFilter.isEmpty || (sort != .custom && !app.player.shuffle)
    }

    private var displayedRows: [TrackRow] {
        let filtered: [TrackRow] = if activeFilter.isEmpty {
            list.rows
        } else {
            list.rows.filter { row in
                row.name.localizedStandardContains(activeFilter)
                    || row.artistNames.localizedStandardContains(activeFilter)
                    || row.album.localizedStandardContains(activeFilter)
            }
        }
        return sort.ordered(filtered, ascending: sortAscending)
    }
}

extension FilterableTrackList where ExtraControls == EmptyView {
    init(
        list: TrackList,
        contextURI: String?,
        columns: [TrackTable.Column] = TrackTable.Column.standard
    ) {
        self.init(list: list, contextURI: contextURI, columns: columns, extraControls: { EmptyView() })
    }
}

/// A track table bound to a `TrackList`, playing rows within its context.
struct TrackListTable: View {
    @Environment(AppModel.self) private var app
    let list: TrackList
    var columns = TrackTable.Column.standard
    var rowsOverride: [TrackRow]? = nil
    var playOverride: ((TrackRow) -> Void)? = nil
    var onRowAppeared: ((Int) -> Void)? = nil
    var editablePlaylist: Playlist? = nil
    var onReorder: ((_ from: Int, _ insertBefore: Int, _ uri: String) -> Void)? = nil

    var body: some View {
        let player = app.player
        let stars = app.stars
        TrackTable(
            rows: rowsOverride ?? list.rows,
            playingURIs: player.playingURIs,
            isPlaybackActive: player.isPlaying,
            starsVersion: stars.version,
            columns: columns,
            actions: .init(
                play: play,
                rowAppeared: onRowAppeared ?? list.pages.appeared,
                isStarred: { stars.isStarred($0.uri) },
                toggleStar: { stars.toggle($0.uri) },
                menu: menu,
                open: { app.navigator.go(to: $0) },
                reorder: onReorder))
    }

    private func play(_ row: TrackRow) {
        if let playOverride {
            playOverride(row)
        } else {
            app.player.play(row, in: list)
        }
    }

    private func menu(for rows: [TrackRow]) -> [TrackMenuItem] {
        guard let first = rows.first else { return [] }
        let (player, library) = (app.player, app.library)
        var items = [
            TrackMenuItem(title: "Play") { play(first) },
            TrackMenuItem(title: "Add to Play Queue") { rows.forEach { player.addToQueue($0.uri) } },
        ]
        let playlists = library.editablePlaylists
        if !playlists.isEmpty {
            items.append(TrackMenuItem(title: "Add to Playlist", children: playlists.map { playlist in
                TrackMenuItem(title: playlist.name) { library.add(rows.map(\.uri), to: playlist) }
            }))
        }
        if let editablePlaylist {
            items.append(TrackMenuItem(title: "Remove from This Playlist") {
                library.removeTracks(rows, from: editablePlaylist, list: list)
            })
        }
        items.append(.separator)
        items += app.songMenu(uri: first.uri, name: first.name, album: first.albumRoute, artists: first.artists)
        items.append(TrackMenuItem(title: "Copy Spotify Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rows.map { Route.webLink(for: $0.uri) }.joined(separator: "\n"), forType: .string)
        })
        return items
    }
}

extension AppModel {
    /// "Show Album", "Show Artist" (a submenu when there are several) and
    /// "Show Credits" for a song, as far as Spotify gives their pages.
    func songMenu(uri: String, name: String, album: Route?, artists: [TrackRow.Artist]) -> [TrackMenuItem] {
        let navigator = navigator
        var items: [TrackMenuItem] = []
        if let album {
            items.append(TrackMenuItem(title: "Show Album") { navigator.go(to: album) })
        }
        let pages = artists.compactMap { artist in
            artist.route.map { route in TrackMenuItem(title: artist.name) { navigator.go(to: route) } }
        }
        if pages.count == 1 {
            items.append(TrackMenuItem(title: "Show Artist", action: pages[0].action))
        } else if !pages.isEmpty {
            items.append(TrackMenuItem(title: "Show Artist", children: pages))
        }
        if let id = Route.trackID(uri) {
            let names = artists.map(\.name).joined(separator: ", ")
            items.append(TrackMenuItem(title: "Show Credits") { [weak self] in
                self?.showCredits(trackID: id, title: name, artists: names)
            })
        }
        return items
    }
}

/// Text in parts separated by commas, the ones with a route links to their
/// page: "A, B" for a song's artists. Links share the text's colour; the
/// font comes from the environment. An optional bold label leads.
struct LinkText: View {
    @Environment(AppModel.self) private var app
    var label: String?
    let parts: [(text: String, route: Route?)]
    let color: Color

    var body: some View {
        var text = AttributedString()
        if let label {
            text = AttributedString("\(label): ")
            text.font = AquaFont.bold(12)
        }
        for (index, part) in parts.enumerated() {
            if index > 0 { text += AttributedString(", ") }
            var run = AttributedString(part.text)
            if part.route != nil { run.link = URL(string: "nanyin-route://\(index)") }
            text += run
        }
        return Text(text)
            .foregroundStyle(color)
            .tint(color)
            .environment(\.openURL, OpenURLAction { url in
                if let index = url.host().flatMap(Int.init), parts.indices.contains(index),
                   let route = parts[index].route {
                    app.navigator.go(to: route)
                }
                return .handled
            })
    }
}

/// The dark band at the top of a page: optional artwork, a title and a
/// line of detail, and controls on the right.
struct PageHeader<Artwork: View, Accessory: View>: View {
    let title: String
    var subtitle = ""
    var description = ""
    @ViewBuilder var artwork: Artwork
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AquaFont.bold(18))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                if !description.isEmpty {
                    Text(description)
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .engraved()
            Spacer(minLength: 0)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.pageHeader)
        .hairline(.bottom, Theme.divider)
    }
}

extension PageHeader where Artwork == EmptyView {
    init(title: String, subtitle: String = "", @ViewBuilder accessory: () -> Accessory) {
        self.init(title: title, subtitle: subtitle, artwork: { EmptyView() }, accessory: accessory)
    }
}

extension PageHeader where Artwork == EmptyView, Accessory == EmptyView {
    init(title: String, subtitle: String = "") {
        self.init(title: title, subtitle: subtitle, artwork: { EmptyView() }, accessory: { EmptyView() })
    }
}

/// Shown in place of a page that has nothing yet.
struct PagePlaceholder: View {
    let title: String
    var message = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title)
            PlaceholderText(message: message)
        }
    }
}

/// A grey line in place of content that is not there, with a way to try
/// again when it failed.
struct PlaceholderText: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(AquaFont.regular(13))
                .foregroundStyle(Theme.secondaryText)
            if let retry {
                Button("Try Again", action: retry).buttonStyle(TexturedButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}
