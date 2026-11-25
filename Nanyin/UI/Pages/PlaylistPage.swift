import NanyinKit
import SwiftUI

/// Sort orders offered in a playlist or Starred action bar.
enum PlaylistSort: CaseIterable, Equatable {
    case custom, title, artist, album, duration, added

    var label: String {
        switch self {
        case .custom: "Custom Order"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .duration: "Time"
        case .added: "Date Added"
        }
    }

    var defaultAscending: Bool { self != .added }

    func buttonLabel(ascending: Bool) -> String {
        self == .custom ? label : "\(label) \(ascending ? "↑" : "↓")"
    }

    func ordered(_ rows: [TrackRow], ascending: Bool) -> [TrackRow] {
        guard self != .custom else { return rows }
        return rows.sorted { lhs, rhs in
            let comparison: ComparisonResult = switch self {
            case .custom: .orderedSame
            case .title: lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .artist: lhs.artistNames.localizedCaseInsensitiveCompare(rhs.artistNames)
            case .album: lhs.album.localizedCaseInsensitiveCompare(rhs.album)
            case .duration:
                lhs.durationMs == rhs.durationMs ? .orderedSame
                    : lhs.durationMs < rhs.durationMs ? .orderedAscending : .orderedDescending
            case .added:
                switch (lhs.addedDate, rhs.addedDate) {
                case let (a?, b?) where a != b: a < b ? .orderedAscending : .orderedDescending
                case (.some, .none): .orderedDescending
                case (.none, .some): .orderedAscending
                default: .orderedSame
                }
            }
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}

/// A playlist page: cover art, details, playback/library/filter/sort controls,
/// drag-reordering on owned playlists, and the track table.
struct PlaylistPage: View {
    @Environment(AppModel.self) private var app
    let playlist: Playlist?
    let list: TrackList

    @State private var editingDetails = false
    @State private var confirmingDelete = false

    var body: some View {
        let pages = list.pages
        let status = pages.error ?? (pages.isLoading && pages.items.isEmpty ? "Loading…" : detail)
        let uri = playlist?.uri ?? list.contextURI
        let editable = playlist.flatMap { app.library.canEditTracks($0) ? $0 : nil }
        let allowReorder = playlist.map(app.library.isOwn) == true

        VStack(spacing: 0) {
            PageHeader(
                title: title,
                subtitle: status,
                description: playlist?.plainDescription ?? ""
            ) {
                CoverImage(url: playlist?.images?.best(minimum: 200), size: 96, fallbackSymbol: "music.note.list")
            } accessory: {
                if pages.error != nil {
                    Button("Try Again", action: pages.retry).buttonStyle(TexturedButtonStyle())
                }
            }
            FilterableTrackList(
                list: list,
                contextURI: uri,
                editablePlaylist: editable,
                allowReorder: allowReorder
            ) {
                if let playlist, !app.library.isOwn(playlist) {
                    let saved = app.library.isSaved(playlistID: playlist.id)
                    Button { app.library.toggleSave(playlist) } label: {
                        Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .buttonStyle(GraphiteToggleStyle(isOn: saved))
                    .disabled(!app.library.canEdit(playlist))
                    .help(saved ? "Remove from Library" : "Add to Library")
                }
                if let uri {
                    moreMenu(uri: uri)
                }
            }
        }
        .sheet(isPresented: $editingDetails) {
            if let playlist {
                EditPlaylistSheet(playlist: playlist) { name, description in
                    app.library.updateDetails(playlist.id, name: name, description: description)
                }
            }
        }
        .alert(
            "Delete “\(playlist?.name ?? "")”?",
            isPresented: $confirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                guard let playlist, app.library.canEdit(playlist) else { return }
                app.navigator.forget(.playlist(id: playlist.id))
                app.library.remove(playlist)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is removed from your library. Spotify keeps it for 90 days, so it can be restored from your account page.")
        }
    }

    private func moreMenu(uri: String) -> some View {
        let library = app.library
        return Menu {
            Button("Play") { app.player.play(contextURI: uri) }
            Button("Shuffle Play") { app.player.play(contextURI: uri, shuffle: true) }
            Divider()
            if let playlist {
                if library.isOwn(playlist) {
                    Button("Edit Details…") { editingDetails = true }
                        .disabled(!library.canEdit(playlist))
                    Button("Delete…") { confirmingDelete = true }
                        .disabled(!library.canEdit(playlist))
                } else {
                    let saved = library.isSaved(playlistID: playlist.id)
                    Button(saved ? "Remove from Library" : "Add to Library") {
                        library.toggleSave(playlist)
                    }
                    .disabled(!library.canEdit(playlist))
                }
                Divider()
            }
            let playlistBusy = playlist.map { library.busy.contains($0.id) } ?? false
            Button(list.pages.isLoading ? "Refreshing…" : "Refresh") {
                list.pages.reload()
            }
            .disabled(list.pages.isLoading || playlistBusy)
            Button("Copy Spotify Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Route.webLink(for: uri), forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.hex(0xC8C8C8))
                .engraved()
                .frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private var title: String {
        guard let name = playlist?.name, !name.isEmpty else { return "Playlist" }
        return name
    }

    private var detail: String {
        let count = list.pages.total.map { $0 == 1 ? "1 track" : "\($0) tracks" }
        let totalDuration: String? = if !list.pages.hasMore, !list.rows.isEmpty {
            TrackRow.formatTotal(ms: list.rows.reduce(0) { $0 + $1.durationMs })
        } else {
            nil
        }
        return [playlist?.ownerName, count, totalDuration].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Sheet to edit an owned playlist's name and description, matching `CreditsSheet`.
private struct EditPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    let onSave: (String, String) -> Void

    @State private var name = ""
    @State private var description = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Edit Playlist", subtitle: playlist.name)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(AquaFont.bold(11))
                        .foregroundStyle(Theme.secondaryText)
                    AquaTextField(text: $name, prompt: "Playlist name")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(AquaFont.bold(11))
                        .foregroundStyle(Theme.secondaryText)
                    let shape = RoundedRectangle(cornerRadius: 4)
                    TextField("Optional description", text: $description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(AquaFont.regular(12))
                        .foregroundStyle(.black)
                        .lineLimit(3 ... 5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(shape.fill(.white))
                        .overlay {
                            shape.stroke(.black.opacity(0.32), lineWidth: 2)
                                .blur(radius: 1)
                                .offset(y: 1)
                                .clipShape(shape)
                        }
                        .overlay(shape.strokeBorder(Theme.hex(0x5A5A5A), lineWidth: 1))
                        .environment(\.colorScheme, .light)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.content)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(TexturedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name, description)
                    dismiss()
                }
                .buttonStyle(TexturedButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Theme.graphite)
            .hairline(.top, Theme.graphiteEdge)
        }
        .frame(width: 360, height: 260)
        .preferredColorScheme(.dark)
        .onAppear {
            name = playlist.name
            description = playlist.plainDescription ?? ""
        }
    }
}
