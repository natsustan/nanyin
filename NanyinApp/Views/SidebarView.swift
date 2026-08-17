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

            sidebarLink("house", "Home")
            sidebarLink("magnifyingglass", "Search")

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

            sidebarLink("heart.fill", "Liked Songs", disabled: true)

            Text("PLAYLISTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            sidebarLink("music.quarternote.3", "Coming in M1…", disabled: true)

            Spacer()

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

    private func sidebarLink(_ icon: String, _ title: String, disabled: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
        }
        .foregroundStyle(disabled ? Theme.textSecondary.opacity(0.6) : Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
