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
            PageHeader(title: title, subtitle: status) {
                if list.error != nil {
                    Button("Try Again", action: list.retry).buttonStyle(TexturedButtonStyle())
                }
            }
            TrackListTable(list: list, columns: columns)
        }
    }

    private var status: String {
        if let error = list.error { return error }
        if let subtitle { return subtitle }
        guard let total = list.total else { return list.isLoading ? "Loading…" : "" }
        return total == 1 ? "1 track" : "\(total) tracks"
    }
}

/// A track table bound to a `TrackList`, playing rows within its context.
struct TrackListTable: View {
    @Environment(AppModel.self) private var app
    let list: TrackList
    var columns = TrackTable.Column.standard

    var body: some View {
        let player = app.player
        TrackTable(
            rows: list.rows,
            playingURI: player.playingURI,
            columns: columns,
            actions: .init(
                play: { player.play($0, in: list) },
                addToQueue: { player.addToQueue($0.uri) },
                togglePlayPause: player.togglePlayPause,
                rowAppeared: list.rowAppeared))
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
