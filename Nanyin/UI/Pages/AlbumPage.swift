import NanyinKit
import SwiftUI

struct AlbumPage: View {
    @Environment(AppModel.self) private var app
    let id: String
    @State private var album: Album?
    @State private var list: TrackList?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if let album {
                HStack(alignment: .top, spacing: 12) {
                    CoverImage(url: album.images?.best(minimum: 200), size: 96)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name).font(AquaFont.bold(18)).foregroundStyle(Theme.text)
                        HStack(spacing: 4) {
                            Text("by").foregroundStyle(Theme.secondaryText)
                            ForEach(album.artists, id: \.self) { artist in
                                Button(artist.name) {
                                    if let id = artist.id { app.navigator.go(to: .artist(id: id)) }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.text)
                            }
                        }
                        .font(AquaFont.regular(12))
                        Text([album.release_date.map { String($0.prefix(4)) }, album.total_tracks.map { "\($0) tracks" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 0)
                        Button("Play") { app.player.play(contextURI: album.uri) }
                            .buttonStyle(TexturedButtonStyle())
                            .environment(\.colorScheme, .light)
                    }
                    Spacer()
                }
                .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                .padding(14)
                .frame(height: 124)
                .background(LinearGradient(colors: [Theme.hex(0x3A3A3A), Theme.hex(0x2C2C2C)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
            } else {
                PageHeader(title: "Album", subtitle: error ?? "Loading…")
            }
            if let list {
                TrackListTable(list: list, columns: [.indicator, .track, .artist, .time])
            } else {
                Theme.content
            }
        }
        .task(id: id) {
            do {
                let loaded = try await app.account.api.album(id)
                album = loaded
                list = .album(loaded)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct ArtistPage: View {
    @Environment(AppModel.self) private var app
    let id: String
    @State private var artist: Artist?
    @State private var topTracks: TrackList?
    @State private var albums: [AlbumSummary] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CoverImage(url: artist?.images?.best(minimum: 200), size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist?.name ?? "Artist").font(AquaFont.bold(18)).foregroundStyle(Theme.text)
                    Text(error ?? artist?.genres?.prefix(3).joined(separator: ", ") ?? "")
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                    if let artist {
                        Button("Play") { app.player.play(contextURI: artist.uri) }
                            .buttonStyle(TexturedButtonStyle())
                            .environment(\.colorScheme, .light)
                    }
                }
                Spacer()
            }
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
            .padding(14)
            .background(LinearGradient(colors: [Theme.hex(0x3A3A3A), Theme.hex(0x2C2C2C)], startPoint: .top, endPoint: .bottom))
            if !albums.isEmpty {
                GraphiteHeader { Text("Albums and Singles") }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            AlbumTile(album: album)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .frame(height: 156)
                .background(Theme.content)
            }
            GraphiteHeader { Text("Popular") }
            if let topTracks {
                TrackListTable(list: topTracks, columns: [.indicator, .track, .time, .popularity, .album])
            } else {
                Theme.content
            }
        }
        .task(id: id) {
            let api = app.account.api
            do {
                async let artist = api.artist(id)
                async let top = api.artistTopTracks(id)
                async let albums = api.artistAlbums(id)
                self.artist = try await artist
                topTracks = .tracks(try await top, contextURI: "spotify:artist:\(id)")
                self.albums = (try? await albums.items) ?? []
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AlbumTile: View {
    @Environment(AppModel.self) private var app
    let album: AlbumSummary

    var body: some View {
        Button {
            app.navigator.go(to: .album(id: album.id))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                CoverImage(url: album.images?.best(minimum: 200), size: 110)
                Text(album.name)
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.text)
                Text(album.release_date.map { String($0.prefix(4)) } ?? "")
                    .font(AquaFont.regular(10))
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .frame(width: 110, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Album art with a thin dark frame, the way the 2010 client framed covers.
struct CoverImage: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Theme.hex(0x404040)
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}
