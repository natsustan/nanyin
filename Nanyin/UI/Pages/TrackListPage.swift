import NanyinKit
import SwiftUI

/// A page that is a title over a track table: Liked Songs, Play Queue.
struct TrackListPage: View {
    let title: String
    var subtitle: String?
    let list: TrackList
    var columns = TrackTable.Column.standard

    var body: some View {
        VStack(spacing: 0) {
            PagerHeader(title: title, pager: list.pages, detail: subtitle ?? count)
            TrackListTable(list: list, columns: columns)
        }
    }

    private var count: String {
        guard let total = list.pages.total else { return "" }
        return total == 1 ? "1 track" : "\(total) tracks"
    }
}

/// A page header that reports a pager's loading and failure, with a way to
/// try again.
struct PagerHeader<Item: Sendable, Cursor: Sendable>: View {
    let title: String
    let pager: Pager<Item, Cursor>
    var detail = ""

    var body: some View {
        let status = pager.error ?? (pager.isLoading && pager.items.isEmpty ? "Loading…" : detail)
        PageHeader(title: title, subtitle: status) {
            if pager.error != nil {
                Button("Try Again", action: pager.retry).buttonStyle(TexturedButtonStyle())
            }
        }
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
    var onReorder: ((_ from: Int, _ insertBefore: Int) -> Void)? = nil

    var body: some View {
        let player = app.player
        let stars = app.stars
        TrackTable(
            rows: rowsOverride ?? list.rows,
            playingURI: player.playingURI,
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
