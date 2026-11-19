import NanyinKit
import SwiftUI

/// A page that is a title over a track table: Liked Songs, a playlist.
struct TrackListPage: View {
    @Environment(AppModel.self) private var app
    let title: String
    let list: TrackList
    var columns: [TrackTable.Column] = [.indicator, .track, .artist, .time, .popularity, .album]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: subtitle)
            TrackListTable(list: list, columns: columns)
        }
    }

    private var subtitle: String {
        if let error = list.error { return error }
        guard let total = list.total else { return list.isLoading ? "Loading…" : "" }
        return total == 1 ? "1 track" : "\(total) tracks"
    }
}

/// A track table bound to a `TrackList`, playing rows within its context.
struct TrackListTable: View {
    @Environment(AppModel.self) private var app
    let list: TrackList
    var columns: [TrackTable.Column] = [.indicator, .track, .artist, .time, .popularity, .album]

    var body: some View {
        let player = app.player
        TrackTable(
            rows: list.rows,
            playingURI: player.playingURI,
            columns: columns,
            actions: .init(
                play: { row in
                    if let context = list.contextURI {
                        player.play(contextURI: context, startURI: row.uri)
                    } else {
                        player.play(trackURIs: list.rows.map(\.uri), startURI: row.uri)
                    }
                },
                addToQueue: { player.addToQueue($0.uri) },
                togglePlayPause: player.togglePlayPause,
                rowAppeared: list.rowAppeared))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AquaFont.bold(18))
                .foregroundStyle(Theme.text)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [Theme.hex(0x3A3A3A), Theme.hex(0x2C2C2C)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
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
