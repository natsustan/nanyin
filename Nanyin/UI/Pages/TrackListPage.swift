import NanyinKit
import SwiftUI

/// A page that is a title over a track table: Liked Songs, a playlist.
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

    var body: some View {
        let player = app.player
        let stars = app.stars
        TrackTable(
            rows: list.rows,
            playingURI: player.playingURI,
            starsVersion: stars.version,
            columns: columns,
            actions: .init(
                play: { player.play($0, in: list) },
                rowAppeared: list.pages.appeared,
                isStarred: { stars.isStarred($0.uri) },
                toggleStar: { stars.toggle($0.uri) },
                menu: menu))
    }

    private func menu(for rows: [TrackRow]) -> [TrackMenuItem] {
        guard let first = rows.first else { return [] }
        let (player, library, navigator) = (app.player, app.library, app.navigator)
        var items = [
            TrackMenuItem(title: "Play") { player.play(first, in: list) },
            TrackMenuItem(title: "Add to Play Queue") { rows.forEach { player.addToQueue($0.uri) } },
        ]
        let playlists = library.editablePlaylists
        if !playlists.isEmpty {
            items.append(TrackMenuItem(title: "Add to Playlist", children: playlists.map { playlist in
                TrackMenuItem(title: playlist.name) { library.add(rows.map(\.uri), to: playlist) }
            }))
        }
        items.append(.separator)
        if let route = first.albumURI.flatMap(Route.init(uri:)) {
            items.append(TrackMenuItem(title: "Show Album") { navigator.go(to: route) })
        }
        if let route = first.artistURI.flatMap(Route.init(uri:)) {
            items.append(TrackMenuItem(title: "Show Artist") { navigator.go(to: route) })
        }
        items.append(TrackMenuItem(title: "Copy Spotify Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rows.map { Route.webLink(for: $0.uri) }.joined(separator: "\n"), forType: .string)
        })
        return items
    }
}

/// The dark band at the top of a page: optional artwork, a title and a
/// line of detail, and controls on the right.
struct PageHeader<Artwork: View, Accessory: View>: View {
    let title: String
    var subtitle = ""
    @ViewBuilder var artwork: Artwork
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AquaFont.bold(18))
                    .foregroundStyle(Theme.text)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .lineLimit(1)
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
            Text(message)
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.content)
        }
    }
}
