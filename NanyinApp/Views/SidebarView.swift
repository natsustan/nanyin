//
//  SidebarView.swift
//  Nanyin
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 8) {
                Image(systemName: "music.note.quarters")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("nanyin")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            entry(.home, icon: "house", title: "Home")
            entry(.search, icon: "magnifyingglass", title: "Search")

            Divider()
                .overlay(Theme.playerBar)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

            Text("YOUR LIBRARY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            entry(.liked, icon: "heart.fill", title: "Liked Songs", count: app.likedCount)

            if !app.playlists.isEmpty {
                Text("PLAYLISTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            } else {
                Text("Loading playlists…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(app.playlists) { playlist in
                        entry(
                            .playlist(id: playlist.id, name: playlist.name),
                            icon: "music.quarternote.3",
                            title: playlist.name,
                            count: playlist.trackCount
                        )
                    }
                }
            }

            if let note = app.connectionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar)
    }

    private func entry(
        _ page: AppModel.Page?,
        icon: String,
        title: String,
        count: Int? = nil,
        disabled: Bool = false
    ) -> some View {
        let isSelected = page != nil && app.page == page

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        }
        .foregroundStyle(
            disabled
                ? Theme.textSecondary.opacity(0.5)
                : (isSelected ? .white : Theme.textSecondary)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color(white: 0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if let page {
                app.open(page)
            }
        }
        .onHover { hovering in
            if hovering, !disabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
