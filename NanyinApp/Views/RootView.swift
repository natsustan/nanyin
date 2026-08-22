//
//  RootView.swift
//  Nanyin
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    var body: some View {
        switch app.authState {
        case .checking, .signingOut:
            VStack(spacing: 12) {
                ProgressView()
                Text(app.authState == .signingOut ? "Signing out…" : "Restoring session…")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.contentBackground.swiftUIStyle)
        case .loggedOut, .signingIn:
            LoginView()
        case .loggedIn:
            AuthenticatedShell()
        }
    }
}
