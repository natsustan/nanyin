import SwiftUI

/// Play Queue page: shows the currently playing song above the upcoming queue,
/// with a button to clear manually queued tracks when any are present.
struct PlayQueuePage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let player = app.player
        let upNext = player.upNext
        VStack(spacing: 0) {
            PageHeader(title: "Play Queue", subtitle: subtitle) {
                if player.hasManualQueue && !player.playingElsewhere {
                    Button("Clear Queue") { player.clearQueue() }
                        .buttonStyle(TexturedButtonStyle())
                        .help("Remove manually added songs from the queue")
                }
            }

            if player.playingElsewhere {
                VStack(spacing: 10) {
                    Text("Playing on another device.")
                        .font(AquaFont.regular(13))
                        .foregroundStyle(Theme.secondaryText)
                    if app.session.isReady {
                        Button("Play on This Mac") { app.connect.transferToThisMac() }
                            .buttonStyle(TexturedButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.content)
            } else {
                if let track = player.track {
                    GraphiteHeader { Text("Now Playing") }
                    nowPlayingRow(track)
                }

                if upNext.rows.isEmpty {
                    if player.track != nil {
                        GraphiteHeader { Text("Next Up") }
                    }
                    PlaceholderText(message: "Songs you add to the queue appear here.")
                } else {
                    GraphiteHeader { Text("Next Up") }
                    TrackListTable(
                        list: upNext,
                        columns: [.star, .track, .artist, .time, .album],
                        playOverride: { row in
                            guard let idx = upNext.rows.firstIndex(where: { $0.id == row.id }) else {
                                app.player.play(trackURI: row.uri)
                                return
                            }
                            if idx == 0 {
                                // Advances directly to the next queued track, keeping both
                                // any remaining manual queue and the full playlist/album context.
                                app.player.next()
                            } else if idx >= player.manualQueueCount, upNext.contextURI != nil {
                                // Context track: start inside the full playlist/album context.
                                app.player.play(row, in: upNext)
                            } else {
                                // Later manually queued track: play from that item onward.
                                app.player.play(rows: Array(upNext.rows[idx...]), start: row)
                            }
                        }
                    )
                }
            }
        }
        .background(Theme.content)
    }

    private var subtitle: String {
        let player = app.player
        if player.playingElsewhere { return "Playing elsewhere" }
        let count = player.upNext.rows.count
        if count == 0 {
            return player.track == nil ? "" : "Playing now"
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
