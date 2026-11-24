import SwiftUI

/// Play Queue page: shows the currently playing song above the upcoming queue,
/// with a button to clear manually queued tracks.
struct PlayQueuePage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let player = app.player
        let upNext = player.upNext
        VStack(spacing: 0) {
            PageHeader(title: "Play Queue", subtitle: subtitle) {
                if !upNext.rows.isEmpty && !player.playingElsewhere {
                    Button("Clear Queue") { player.clearQueue() }
                        .buttonStyle(TexturedButtonStyle())
                        .help("Remove manually added songs from the queue")
                }
            }

            if let track = player.track {
                GraphiteHeader { Text("Now Playing") }
                nowPlayingRow(track)
            }

            if upNext.rows.isEmpty {
                if player.track != nil {
                    GraphiteHeader { Text("Next Up") }
                }
                PlaceholderText(
                    message: player.playingElsewhere
                        ? "Playing on another device."
                        : "Songs you add to the queue appear here."
                )
            } else {
                GraphiteHeader { Text("Next Up") }
                TrackListTable(list: upNext, columns: [.star, .track, .artist, .time, .album])
            }
        }
        .background(Theme.content)
    }

    private var subtitle: String {
        let count = app.player.upNext.rows.count
        if count == 0 {
            return app.player.track == nil ? "" : "Playing now"
        }
        return count == 1 ? "1 track up next" : "\(count) tracks up next"
    }

    private func nowPlayingRow(_ track: CoreTrack) -> some View {
        HStack(spacing: 10) {
            CoverImage(url: track.coverURL, size: 36, fallbackSymbol: "music.note")
            VStack(alignment: .leading, spacing: 2) {
                LinkText(
                    parts: [(track.name, track.albumURI.flatMap(Route.init(uri:)))],
                    color: Theme.green
                )
                .font(AquaFont.bold(12.5))
                LinkText(
                    parts: track.artists.map { ($0.name, Route(uri: $0.uri)) },
                    color: Theme.secondaryText
                )
                .font(AquaFont.regular(11.5))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if !track.album.isEmpty {
                LinkText(
                    parts: [(track.album, track.albumURI.flatMap(Route.init(uri:)))],
                    color: Theme.secondaryText
                )
                .font(AquaFont.regular(11.5))
                .lineLimit(1)
            }
            Text(TrackRow.format(ms: track.durationMs))
                .font(AquaFont.regular(11.5))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: Theme.row(0)))
        .hairline(.bottom, Theme.divider)
        .contextMenu {
            TrackMenuContent(items: app.songMenu(
                uri: track.uri,
                name: track.name,
                album: track.albumURI.flatMap(Route.init(uri:)),
                artists: track.artists.map(TrackRow.Artist.init)
            ))
        }
    }
}
