import NanyinKit
import SwiftUI

/// Artist page in the 2010 Spotify-for-Mac style: fixed header with stats and
/// actions, above a single scrolling view of Popular tracks (with play counts),
/// categorized paginated Discography grid, and Fans Also Like.
struct ArtistPage: View {
    @Environment(AppModel.self) private var app
    let detail: ArtistDetail

    @State private var contentWidth: CGFloat = 720
    @State private var expandedRelated = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: detail.artist?.name ?? "Artist",
                subtitle: headerSubtitle
            ) {
                CoverImage(url: detail.artist?.images?.best(minimum: 200), size: 80)
            } accessory: {
                if let artist = detail.artist {
                    HStack(spacing: 6) {
                        LibraryToggleButton(
                            status: detail.libraryStatus,
                            addedTitle: "Following",
                            addTitle: "Follow",
                            disabled: detail.isUpdatingFollow,
                            toggle: detail.toggleFollow,
                            retry: detail.retryLibraryStatus
                        )
                        Button("Play") { app.player.play(contextURI: artist.uri) }
                            .buttonStyle(TexturedButtonStyle())
                    }
                } else if detail.error != nil {
                    Button("Try Again") { detail.retryArtist() }
                        .buttonStyle(TexturedButtonStyle())
                }
            }

            let layout = CoverGridMetrics.compute(width: contentWidth)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    popularSection
                    EtchedDivider()
                    discographySection(layout: layout)
                    if !detail.relatedArtists.isEmpty {
                        EtchedDivider()
                        relatedSection(layout: layout)
                    }
                }
                .padding(.horizontal, layout.padding)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(Theme.content)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            if proxy.size.width > 0 { contentWidth = proxy.size.width }
                        }
                        .onChange(of: proxy.size.width) { _, width in
                            if width > 0 { contentWidth = width }
                        }
                }
            )
        }
    }

    private var headerSubtitle: String {
        if let error = detail.error, detail.artist == nil {
            return error
        }
        var parts: [String] = []
        if let listeners = detail.monthlyListeners {
            let suffix = listeners == 1 ? "monthly listener" : "monthly listeners"
            parts.append("\(listeners.formatted()) \(suffix)")
        }
        if let followers = detail.followersCount {
            let suffix = followers == 1 ? "follower" : "followers"
            parts.append("\(followers.formatted()) \(suffix)")
        }
        if let genres = detail.artist?.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Popular

    private var popularSection: some View {
        let pages = detail.topTracks.pages
        let rows = pages.items
        let displayed = detail.showAllTopTracks ? rows : Array(rows.prefix(5))
        let hasPlays = rows.contains { detail.playCount(for: $0.uri) != nil }
        let showAlbum = contentWidth >= 520

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                sectionHeading("Popular")
                Spacer(minLength: 8)
                if rows.count > 5 {
                    Button(detail.showAllTopTracks ? "Show Less" : "See More") {
                        detail.toggleShowAllTopTracks()
                    }
                    .buttonStyle(MetalPillButtonStyle())
                }
            }

            if rows.isEmpty {
                inlineStatus(
                    message: pages.error ?? (pages.isLoading ? "Loading…" : "No popular songs."),
                    retry: pages.error == nil ? nil : { pages.retry() }
                )
            } else {
                // Observe star changes so star icons repaint immediately.
                let _ = app.stars.version
                VStack(spacing: 0) {
                    popularHeader(showAlbum: showAlbum, showPlays: hasPlays)
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, row in
                        PopularTrackRow(
                            rank: index + 1,
                            row: row,
                            playCount: detail.playCount(for: row.uri),
                            showAlbum: showAlbum,
                            showPlays: hasPlays,
                            isPlaying: app.player.playingURIs.contains(row.uri),
                            isPlaybackActive: app.player.isPlaying,
                            isStarred: app.stars.isStarred(row.uri),
                            onPlay: { app.player.play(row, in: detail.topTracks) },
                            onToggleStar: { app.stars.toggle(row.uri) },
                            onOpen: { app.navigator.go(to: $0) },
                            menuItems: { trackMenu(for: row) }
                        )
                    }
                }
                .overlay(Rectangle().strokeBorder(Theme.divider, lineWidth: 1))
            }
        }
    }

    private func popularHeader(showAlbum: Bool, showPlays: Bool) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 28, alignment: .trailing)
                .padding(.trailing, 4)
            Spacer().frame(width: 24)
            Text("Track")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
            if showAlbum {
                Text("Album")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 10)
            }
            if showPlays {
                Text("Plays")
                    .frame(width: 96, alignment: .trailing)
                    .padding(.trailing, 10)
            }
            Text("Time")
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .font(AquaFont.bold(11))
        .foregroundStyle(Theme.text)
        .frame(height: 21)
        .background(Theme.graphite)
        .hairline(.top, Theme.graphiteHighlight)
        .hairline(.bottom, Theme.graphiteEdge)
    }

    private func trackMenu(for row: TrackRow) -> [TrackMenuItem] {
        app.trackMenu(for: [row]) { app.player.play($0, in: detail.topTracks) }
    }

    // MARK: Discography

    private func discographySection(layout: CoverGridMetrics) -> some View {
        let pager = detail.currentDiscography
        let albums = detail.visibleDiscography

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Discography")

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(ArtistAlbumGroup.allCases, id: \.self) { group in
                        Button(group.label) {
                            detail.selectGroup(group)
                        }
                        .buttonStyle(DarkSegmentButtonStyle(selected: detail.selectedGroup == group))
                    }
                }
            }
            .scrollIndicators(.hidden)

            if albums.isEmpty {
                if pager?.isLoading ?? true {
                    inlineStatus(message: "Loading…", minHeight: 110)
                } else if let error = pager?.error {
                    inlineStatus(message: error, minHeight: 110) { pager?.retry() }
                } else {
                    inlineStatus(message: "No releases in this category.", minHeight: 72)
                }
            } else {
                LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: 18) {
                    ForEach(albums) { album in
                        Tile(album: album, subtitle: album.releaseSubtitle, size: layout.tileSize)
                    }
                }
                if pager?.isLoading == true {
                    Text("Loading more…")
                        .font(AquaFont.regular(11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                } else if let error = pager?.error {
                    HStack(spacing: 10) {
                        Text(error)
                            .font(AquaFont.regular(11.5))
                            .foregroundStyle(Theme.secondaryText)
                        Button("Try Again") { pager?.retry() }
                            .buttonStyle(TexturedButtonStyle())
                    }
                    .padding(.top, 4)
                } else if pager?.hasMore == true {
                    Button("Load More") {
                        pager?.loadNext()
                    }
                    .buttonStyle(MetalPillButtonStyle())
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Fans Also Like

    private func relatedSection(layout: CoverGridMetrics) -> some View {
        let items = detail.relatedArtists
        let hasMore = items.count > layout.columns
        let displayed = (hasMore && !expandedRelated) ? Array(items.prefix(layout.columns)) : items

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                sectionHeading("Fans Also Like")
                Spacer(minLength: 8)
                if hasMore {
                    Button(expandedRelated ? "Show Less" : "More") {
                        expandedRelated.toggle()
                    }
                    .buttonStyle(MetalPillButtonStyle())
                    .help(expandedRelated ? "Show fewer artists" : "Show all \(items.count) artists")
                }
            }
            LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: 18) {
                ForEach(displayed) { artist in
                    Tile(artist: artist, subtitle: "Artist", size: layout.tileSize)
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(AquaFont.bold(14))
            .foregroundStyle(Theme.green)
    }

    private func inlineStatus(message: String, minHeight: CGFloat = 64, retry: (() -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(AquaFont.regular(12.5))
                .foregroundStyle(Theme.secondaryText)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(TexturedButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

/// One zebra-striped row in the Artist page's Popular list, matching the
/// 2010 Spotify track table without nesting a second vertical NSScrollView.
private struct PopularTrackRow: View {
    let rank: Int
    let row: TrackRow
    let playCount: UInt64?
    let showAlbum: Bool
    let showPlays: Bool
    let isPlaying: Bool
    let isPlaybackActive: Bool
    let isStarred: Bool?
    let onPlay: () -> Void
    let onToggleStar: () -> Void
    let onOpen: (Route) -> Void
    let menuItems: () -> [TrackMenuItem]

    @State private var hovering = false
    @State private var hoveringAlbum = false

    var body: some View {
        let primaryColor: Color = isPlaying ? Theme.green : (row.isPlayable ? Theme.text : Theme.secondaryText.opacity(0.55))
        let secondaryColor: Color = isPlaying ? Theme.green.opacity(0.85) : Theme.secondaryText

        HStack(spacing: 0) {
            // Rank / Speaker / Hover play trigger
            Button(action: onPlay) {
                Group {
                    if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isPlaying ? Theme.green : Theme.text)
                    } else if isPlaying {
                        Image(systemName: isPlaybackActive ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.green)
                    } else {
                        Text("\(rank)")
                            .font(AquaFont.regular(11.5).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(width: 28, height: 24, alignment: .trailing)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Star button
            Button(action: onToggleStar) {
                Group {
                    if let isStarred {
                        Image(systemName: isStarred ? "star.fill" : "star")
                            .font(.system(size: 10.5))
                            .foregroundStyle(isStarred ? Theme.star : Theme.secondaryText.opacity(hovering ? 0.75 : 0.35))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isStarred == nil)

            // Track title
            Text(row.name)
                .font(isPlaying ? AquaFont.bold(12) : AquaFont.regular(12))
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)

            // Album link
            if showAlbum {
                Group {
                    if let route = row.albumRoute, !row.album.isEmpty {
                        Button { onOpen(route) } label: {
                            Text(row.album)
                                .font(AquaFont.regular(11.5))
                                .foregroundStyle(hoveringAlbum ? Theme.text : secondaryColor)
                                .underline(hoveringAlbum)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveringAlbum = $0 }
                        .linkPointer(hoveringAlbum)
                    } else {
                        Text(row.album)
                            .font(AquaFont.regular(11.5))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.trailing, 10)
            }

            // Play count
            if showPlays {
                Text(playCount.map { $0.formatted() } ?? "")
                    .font(AquaFont.regular(11.5).monospacedDigit())
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .trailing)
                    .padding(.trailing, 10)
            }

            // Duration
            Text(row.duration)
                .font(AquaFont.regular(11.5).monospacedDigit())
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: 25)
        .background(Theme.rowColor(rank - 1))
        .overlay(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .contextMenu {
            TrackMenuContent(items: menuItems())
        }
    }
}
