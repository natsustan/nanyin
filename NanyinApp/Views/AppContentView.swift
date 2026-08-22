//
//  AppContentView.swift
//  Nanyin
//

import SwiftUI

/// Shared page owner used by both shell presentations. Shells own geometry;
/// page views own data loading and page-specific interaction.
struct AppContentView: View {
    @Environment(AppModel.self) private var app

    @ViewBuilder
    var body: some View {
        switch app.page {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .queue:
            QueueView()
        case .liked:
            PlaylistDetailView(
                title: "Liked Songs",
                subtitle: "\(app.likedCount) songs · \(app.userDisplayName)",
                coverURL: nil,
                contextKey: "liked",
                coverAssetName: "LikedSongsCover"
            )
        case .savedAlbums:
            SavedAlbumsView()
        case let .playlist(id, name):
            let info = app.playlists.first { $0.id == id }
            PlaylistDetailView(
                title: name,
                subtitle: "\(info?.trackCount ?? (app.tracksByContext[id]?.count ?? 0)) songs",
                coverURL: info?.artworkURL,
                contextKey: id
            )
        case let .artist(id, name, artworkURL):
            ArtistDetailView(
                artistID: id,
                title: name,
                artworkURL: artworkURL,
                contextKey: AppModel.artistContextKey(id)
            )
        case let .album(id, name, subtitle, artworkURL):
            PlaylistDetailView(
                title: name,
                subtitle: subtitle,
                coverURL: artworkURL,
                contextKey: AppModel.albumContextKey(id),
                label: "ALBUM",
                albumId: id
            )
        }
    }
}
