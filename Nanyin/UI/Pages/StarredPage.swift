import NanyinKit
import SwiftUI

/// Starred (Liked Songs) page with the same Play, Shuffle, in-page Filter, and
/// Sort action bar as `PlaylistPage`.
struct StarredPage: View {
    @Environment(AppModel.self) private var app
    let list: TrackList

    @State private var filter = ""
    @State private var reachedFilteredEnd = false
    @State private var sort: PlaylistSort = .custom
    @State private var sortAscending = true

    var body: some View {
        let pages = list.pages
        let displayed = displayedRows
        let uri = list.contextURI
        let fetchFilteredMore = !trimmedFilter.isEmpty && pages.hasMore && (displayed.count < 20 || reachedFilteredEnd)

        VStack(spacing: 0) {
            PagerHeader(title: "Starred", pager: pages, detail: count)
            actionBar(displayed: displayed, uri: uri)
            if !trimmedFilter.isEmpty && displayed.isEmpty {
                if pages.hasMore {
                    PlaceholderText(
                        message: pages.error ?? "Searching more tracks…",
                        retry: pages.error != nil ? { pages.retry() } : nil
                    )
                } else {
                    PlaceholderText(message: "No matching tracks.")
                }
            } else {
                TrackListTable(
                    list: list,
                    columns: [.star, .track, .artist, .time, .album, .added],
                    rowsOverride: isCustomView ? displayed : nil,
                    playOverride: playDisplayed ? { row in
                        app.player.play(rows: displayed, start: row, contextURI: uri)
                    } : nil,
                    onRowAppeared: isCustomView ? { index in
                        if index >= displayed.count - 20 {
                            if !trimmedFilter.isEmpty { reachedFilteredEnd = true }
                            list.pages.loadNext()
                        }
                    } : nil
                )
            }
        }
        .task(id: fetchFilteredMore ? "\(trimmedFilter)|\(pages.items.count)" : "") {
            guard fetchFilteredMore else { return }
            pages.loadNext()
        }
        .onChange(of: trimmedFilter) { reachedFilteredEnd = false }
        .onChange(of: displayed.count) { reachedFilteredEnd = false }
    }

    private func actionBar(displayed: [TrackRow], uri: String?) -> some View {
        let player = app.player
        let controlsCurrent = uri != nil && !isCustomView && player.contextURI == uri && player.track != nil
        let isPlayingHere = controlsCurrent && player.isPlaying
        let canPlay = playDisplayed ? !displayed.isEmpty : (!list.rows.isEmpty || (list.pages.total ?? 1) > 0)

        return HStack(spacing: 8) {
            Button {
                if controlsCurrent {
                    player.togglePlayPause()
                } else if playDisplayed {
                    player.play(rows: displayed, contextURI: uri)
                } else if let uri {
                    player.play(contextURI: uri)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isPlayingHere ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(isPlayingHere ? "Pause" : "Play")
                }
            }
            .buttonStyle(TexturedButtonStyle())
            .disabled(uri == nil || (!controlsCurrent && !canPlay))

            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
            }
            .buttonStyle(GraphiteToggleStyle(isOn: player.shuffle))
            .help(player.shuffle ? "Turn Shuffle Off" : "Turn Shuffle On")

            Spacer(minLength: 8)

            AquaSearchField(text: $filter, prompt: "Filter")
                .frame(width: 170)

            sortMenu
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
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
                .font(AquaFont.regular(11))
        }
        .menuStyle(.button)
        .buttonStyle(TexturedButtonStyle())
        .fixedSize()
    }

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCustomView: Bool {
        !trimmedFilter.isEmpty || sort != .custom
    }

    private var playDisplayed: Bool {
        !trimmedFilter.isEmpty || (sort != .custom && !app.player.shuffle)
    }

    private var displayedRows: [TrackRow] {
        let filtered: [TrackRow] = if trimmedFilter.isEmpty {
            list.rows
        } else {
            list.rows.filter { row in
                row.name.localizedStandardContains(trimmedFilter)
                    || row.artistNames.localizedStandardContains(trimmedFilter)
                    || row.album.localizedStandardContains(trimmedFilter)
            }
        }
        return sort.ordered(filtered, ascending: sortAscending)
    }

    private var count: String {
        guard let total = list.pages.total else { return "" }
        return total == 1 ? "1 track" : "\(total) tracks"
    }
}
