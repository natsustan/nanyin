//
//  RootView.swift
//  Nanyin
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.authState {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Restoring session…")
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        case .loggedOut, .signingIn:
            LoginView()
        case .loggedIn:
            mainLayout
        }
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 230)
                Divider().overlay(Theme.playerBar)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Theme.playerBar)
            PlayerBar()
                .frame(height: 84)
        }
        .background(Theme.background)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
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
