import NanyinKit
import SwiftUI
import UniformTypeIdentifiers

/// The source list: brushed-metal account & new-playlist header, fixed
/// destinations, the library, the playlists, and the cover of what is playing
/// at the bottom, following the 2010 Spotify-for-Mac layout.
struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Read once here so a navigation redraws only the two rows whose
        // selection changed.
        let current = app.navigator.current
        let go = app.navigator.go
        let activeContext = app.player.contextURI
        let isPlaying = app.player.isPlaying
        let starredURI = app.account.profile.map { "spotify:user:\($0.id):collection" }
        VStack(spacing: 0) {
            SidebarHeaderBar()
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.fixed, id: \.route) { item in
                            if let heading = item.heading { SidebarHeading(title: heading) }
                            let itemPlaying = item.route == .likedSongs && starredURI != nil && activeContext == starredURI
                            SidebarRow(
                                title: item.title,
                                icon: item.icon,
                                iconTint: item.tint,
                                isSelected: current == item.route,
                                isPlayingContext: itemPlaying,
                                isPlaybackActive: isPlaying,
                                onDoubleClick: item.route == .likedSongs ? {
                                    if let starredURI { app.player.play(contextURI: starredURI) }
                                } : nil
                            ) {
                                go(item.route, false)
                            }
                        }
                        EtchedDivider()
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        SidebarHeading(title: "Playlists")
                            .id("new-playlist-anchor")
                            .contextMenu { newPlaylistButton }
                        if library.edit == .new {
                            SidebarNameField(initial: "New Playlist") { name in
                                library.edit = nil
                                guard let name else { return }
                                let navigator = app.navigator
                                let from = navigator.current
                                Task {
                                    // Opened unless the listener has moved on meanwhile.
                                    if let playlist = await library.createPlaylist(named: name), navigator.current == from {
                                        go(.playlist(id: playlist.id), false)
                                    }
                                }
                            }
                        } else if let creating = library.creating {
                            SidebarRow(title: creating, icon: "music.note.list", isSelected: false) {}
                                .opacity(0.5)
                        }
                        ForEach(library.playlists) { playlist in
                            let route = Route.playlist(id: playlist.id)
                            if library.edit == .rename(id: playlist.id) {
                                SidebarNameField(initial: playlist.name) { name in
                                    library.edit = nil
                                    if let name { library.rename(playlist.id, to: name) }
                                }
                            } else {
                                let rowView = SidebarRow(
                                    title: playlist.name,
                                    icon: "music.note.list",
                                    isSelected: current == route,
                                    isDropTargeted: dropTargetPlaylistID == playlist.id,
                                    isPlayingContext: activeContext == playlist.uri,
                                    isPlaybackActive: isPlaying,
                                    onDoubleClick: { app.player.play(contextURI: playlist.uri) }
                                ) {
                                    go(route, false)
                                }
                                .contextMenu { playlistMenu(playlist) }

                                if library.canEditTracks(playlist) {
                                    rowView.onDrop(
                                        of: [.utf8PlainText, .plainText, .url],
                                        isTargeted: Binding(
                                            get: { dropTargetPlaylistID == playlist.id },
                                            set: { targeted in
                                                if targeted {
                                                    dropTargetPlaylistID = playlist.id
                                                } else if dropTargetPlaylistID == playlist.id {
                                                    dropTargetPlaylistID = nil
                                                }
                                            }
                                        )
                                    ) { providers in
                                        handleTrackDrop(providers, onto: playlist)
                                    }
                                } else {
                                    rowView
                                }
                            }
                        }
                        if let error = app.library.playlistsError {
                            Text(error)
                                .font(AquaFont.regular(11))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        Color.clear
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                            .contextMenu { newPlaylistButton }
                    }
                    .padding(.top, 5)
                    .padding(.bottom, 6)
                }
                .onChange(of: library.edit) { _, edit in
                    if edit == .new {
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollProxy.scrollTo("new-playlist-anchor", anchor: .top)
                        }
                    }
                }
            }
            NowPlayingCover()
        }
        .background(Theme.sidebar)
        .alert(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { playlist in
            Button("Delete", role: .destructive) { remove(playlist) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from your library. Spotify keeps it for 90 days, so it can be restored from your account page.")
        }
    }

    @State private var deleting: Playlist?
    @State private var dropTargetPlaylistID: String?

    private var library: Library { app.library }

    private func handleTrackDrop(_ providers: [NSItemProvider], onto playlist: Playlist) -> Bool {
        let matching = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !matching.isEmpty else { return false }
        let library = app.library
        let expectedAccount = library.accountGeneration
        Task {
            var uris: [String] = []
            var seen = Set<String>()
            for provider in matching {
                if let text = await Self.loadDroppedString(from: provider) {
                    for token in text.split(whereSeparator: \.isNewline) {
                        if case .track(let id) = SpotifyLink.parse(String(token)) {
                            let uri = "spotify:track:\(id)"
                            if seen.insert(uri).inserted { uris.append(uri) }
                        }
                    }
                }
            }
            guard !uris.isEmpty else { return }
            library.add(uris, to: playlist, expectedAccount: expectedAccount)
        }
        return true
    }

    private static func loadDroppedString(from provider: NSItemProvider) async -> String? {
        for type in [UTType.utf8PlainText, UTType.plainText, UTType.url]
            where provider.hasItemConformingToTypeIdentifier(type.identifier)
        {
            let value: String? = await withCheckedContinuation { continuation in
                Self.loadItemText(provider, typeIdentifier: type.identifier) { text in
                    continuation.resume(returning: text)
                }
            }
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    /// Invokes `NSItemProvider.loadItem` with a `nonisolated` completion handler
    /// because AppKit delivers the loaded item on a background queue.
    private nonisolated static func loadItemText(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            if let string = item as? String {
                completion(string)
            } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                completion(string)
            } else if let url = item as? URL {
                completion(url.absoluteString)
            } else {
                completion(nil)
            }
        }
    }

    private var newPlaylistButton: some View {
        Button("New Playlist") { library.begin(.new) }
            .disabled(!library.canEditPlaylists)
    }

    @ViewBuilder private func playlistMenu(_ playlist: Playlist) -> some View {
        Button("Play") { app.player.play(contextURI: playlist.uri) }
        Divider()
        Group {
            if library.isOwn(playlist) {
                Button("Rename") { library.begin(.rename(id: playlist.id)) }
                Button("Delete…") { deleting = playlist }
            } else {
                Button("Remove from Library") { remove(playlist) }
            }
        }
        .disabled(!library.canEdit(playlist))
        Divider()
        Button("Copy Spotify Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Route.webLink(for: playlist.uri), forType: .string)
        }
        Divider()
        newPlaylistButton
    }

    /// Its page goes from history too, and is left if showing.
    private func remove(_ playlist: Playlist) {
        guard library.canEdit(playlist) else { return }
        app.navigator.forget(.playlist(id: playlist.id))
        library.remove(playlist)
    }

    private struct Item {
        var heading: String?
        let title: String
        let icon: String
        var tint: Color? = nil
        let route: Route
    }

    private static let fixed = [
        Item(title: "What's New", icon: "house", route: .whatsNew),
        Item(title: "Play Queue", icon: "list.bullet", route: .queue),
        Item(heading: "Library", title: "Starred", icon: "star.fill", tint: Theme.star, route: .likedSongs),
        Item(title: "Albums", icon: "square.stack", route: .albums),
        Item(title: "Artists", icon: "music.mic", route: .artists),
    ]
}

/// The 24-pt brushed-metal bar at the top of the sidebar (matching the 2010
/// Spotify-for-Mac mockup): the listener's name as an account menu on the
/// left, and a recessed square retro `+` button on the right to create a
/// playlist directly.
private struct SidebarHeaderBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.openSettings) private var openSettings
    @State private var hoveringAccount = false

    var body: some View {
        MetalSubBar {
            Menu {
                if let profile = app.account.profile {
                    Text(profile.isPremium ? "\(profile.name) · Premium" : profile.name)
                }
                Divider()
                Button("New Playlist") { app.library.begin(.new) }
                    .disabled(!app.library.canEditPlaylists)
                Button("Settings…") { openSettings() }
                Divider()
                Button("Sign Out") { Task { await app.signOut() } }
            } label: {
                HStack(spacing: 4) {
                    Text(app.account.profile?.name ?? "Library")
                        .font(AquaFont.bold(12))
                        .foregroundStyle(Theme.metalText.opacity(appearsActive ? 1 : 0.65))
                        .embossed()
                        .lineLimit(1)
                    if hoveringAccount {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Theme.metalSecondaryText)
                            .embossed()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(hoveringAccount ? Theme.subBarHover : Color.clear)
            .contentShape(Rectangle())
            .environment(\.colorScheme, .light)
            .onHover { hoveringAccount = $0 }
            .help("Account & Settings")

            MetalSubBarDivider()

            Button {
                app.library.begin(.new)
            } label: {
                RetroPlusGlyph()
            }
            .buttonStyle(MetalSubBarButtonStyle(width: 26))
            .disabled(!app.library.canEditPlaylists)
            .help("New Playlist (⌘N)")
        }
    }
}

/// Chunky, pixel-crisp 2010 Aqua `+` glyph drawn as two perpendicular bars.
private struct RetroPlusGlyph: View {
    var body: some View {
        ZStack {
            Rectangle().frame(width: 10, height: 2.5)
            Rectangle().frame(width: 2.5, height: 10)
        }
    }
}

/// A playlist's name being typed in place of its row: Return keeps it,
/// Escape (or an empty name) gives up, clicking elsewhere keeps it.
/// `Library` trims the name and ignores an empty one.
private struct SidebarNameField: View {
    let initial: String
    /// The typed name, or nil when editing was cancelled.
    let done: (String?) -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(Theme.sidebarHeading)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 3)
                .background(Theme.content)
                .overlay(Rectangle().strokeBorder(Theme.selection, lineWidth: 1))
                .focused($focused)
                .onSubmit { finish(text) }
                .onExitCommand { finish(nil) }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .onAppear {
            text = initial
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { finish(text) }
        }
    }

    private func finish(_ name: String?) {
        guard !finished else { return }
        finished = true
        done(name)
    }
}

private struct SidebarHeading: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(AquaFont.bold(10.5))
            .foregroundStyle(Theme.sidebarHeading)
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }
}

private struct SidebarRow: View {
    @Environment(\.appearsActive) private var appearsActive
    let title: String
    let icon: String
    var iconTint: Color? = nil
    let isSelected: Bool
    var isDropTargeted = false
    var isPlayingContext = false
    var isPlaybackActive = false
    var onDoubleClick: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        let selectedInk = Theme.sidebarSelectionText
        let row = HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(
                    isSelected
                        ? (iconTint ?? selectedInk)
                        : (iconTint ?? Theme.sidebarHeading)
                )
            Text(title)
                .font(isSelected ? AquaFont.bold(12) : AquaFont.regular(12))
                .foregroundStyle(isSelected ? selectedInk : Theme.sidebarText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isPlayingContext {
                Image(systemName: isPlaybackActive ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? selectedInk : Theme.green)
            }
        }
        .shadow(
            color: isSelected ? .white.opacity(0.45) : .black.opacity(0.35),
            radius: 0,
            y: 1
        )
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background {
            if isSelected {
                Theme.sidebarSelection(active: appearsActive)
                    .hairline(.top, Theme.sidebarSelectionEdgeTop)
                    .hairline(.bottom, Theme.sidebarSelectionEdgeBottom)
            } else if isDropTargeted {
                Theme.green.opacity(0.22)
            }
        }
        .overlay {
            if isDropTargeted {
                Rectangle().strokeBorder(Theme.green, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())

        if let onDoubleClick {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
        } else {
            Button(action: action) { row }
                .buttonStyle(.plain)
        }
    }
}

/// The playing track's title and its cover, filling the sidebar's width,
/// or folded down to a thumbnail beside the title. The title opens the
/// album, each artist their page.
private struct NowPlayingCover: View {
    @Environment(AppModel.self) private var app
    @AppStorage("NowPlayingArtworkLarge") private var large = true
    @State private var hovering = false

    var body: some View {
        let _ = app.stars.version
        if let track = app.player.track {
            let starred = track.isTrack ? app.stars.isStarred(track.uri) : nil
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    if !large {
                        Button { large = true } label: {
                            CoverImage(url: track.coverURL, size: 32)
                                .overlay { if hovering { ArtworkToggle(symbol: "arrow.up.left.and.arrow.down.right") } }
                        }
                        .buttonStyle(.plain)
                        .help("Show Large Artwork")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        LinkText(parts: [(track.name, track.albumURI.flatMap(Route.init(uri:)))], color: Theme.text)
                            .font(AquaFont.bold(12))
                        if app.player.playingElsewhere {
                            HStack(spacing: 4) {
                                Text("Playing elsewhere")
                                    .font(AquaFont.regular(11))
                                    .foregroundStyle(Theme.secondaryText)
                                if app.session.isReady {
                                    Button("Play Here") { app.connect.transferToThisMac() }
                                        .buttonStyle(.link)
                                        .font(AquaFont.bold(11))
                                        .foregroundStyle(Theme.green)
                                }
                            }
                        } else {
                            LinkText(parts: track.artists.map { ($0.name, Route(uri: $0.uri)) }, color: Theme.secondaryText)
                                .font(AquaFont.regular(11))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if track.isTrack {
                        let isStarred = starred == true
                        Button { app.stars.toggle(track.uri) } label: {
                            Image(systemName: isStarred ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(isStarred ? Theme.star : Theme.secondaryText.opacity(starred == nil ? 0.35 : 0.75))
                                .engraved()
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isStarred ? "Remove from Starred" : "Add to Starred")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.graphite)
                .hairline(.top, Theme.graphiteEdge)
                .hairline(.bottom, Theme.divider)
                if large {
                    Artwork(url: track.coverURL, placeholder: Theme.vinylBackground) {
                        VinylPlaceholder(insetRatio: 0.09)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if hovering {
                            Button { large = false } label: {
                                ArtworkToggle(symbol: "arrow.down.right.and.arrow.up.left")
                            }
                            .buttonStyle(.plain)
                            .help("Hide Large Artwork")
                            .padding(6)
                        }
                    }
                }
            }
            .onHover { hovering = $0 }
            .contextMenu { menu(track) }
        }
    }

    @ViewBuilder private func menu(_ track: CoreTrack) -> some View {
        if track.isTrack {
            let isStarred = app.stars.isStarred(track.uri) == true
            Button(isStarred ? "Remove from Starred" : "Add to Starred") {
                app.stars.toggle(track.uri)
            }
            Divider()
        }
        TrackMenuContent(items: app.songMenu(
            uri: track.uri, name: track.name, album: track.albumURI.flatMap(Route.init(uri:)),
            artists: track.artists.map(TrackRow.Artist.init)))
        Divider()
        Button(large ? "Hide Large Artwork" : "Show Large Artwork") { large.toggle() }
    }
}

/// The small dark button over the artwork that folds it up or out.
private struct ArtworkToggle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.artworkButtonGlyph)
            .frame(width: 16, height: 16)
            .background(Theme.artworkButton, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.artworkButtonEdge, lineWidth: 0.5))
    }
}
