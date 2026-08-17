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
                    .frame(width: 220)
                Divider().overlay(Theme.playerBar)
                HomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Theme.playerBar)
            PlayerBar()
                .frame(height: 84)
        }
        .background(Theme.background)
        .ignoresSafeArea()
    }
}
