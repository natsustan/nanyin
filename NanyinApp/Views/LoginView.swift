//
//  LoginView.swift
//  Nanyin
//

import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "music.note.quarters")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(theme.colors.accent)
                Text("nanyin")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
                Text("Native Spotify client for macOS")
                    .foregroundStyle(theme.colors.secondaryText)
            }

            switch app.authState {
            case .signingIn:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Complete the sign-in in your browser…")
                        .font(.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            default:
                Button {
                    app.signIn()
                } label: {
                    Text("CONNECT WITH SPOTIFY")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.colors.inverseText)
                        .padding(.horizontal, theme.metrics.controlHorizontalPadding + 6)
                        .padding(.vertical, theme.metrics.controlVerticalPadding + 3)
                        .background(theme.colors.accent)
                        .cornerRadius(theme.metrics.heroPillCornerRadius)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            if let error = app.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, theme.metrics.pageHorizontalInset + 12)
            }

            Text("Requires Spotify Premium. Unofficial client — not affiliated with Spotify.")
                .font(.caption2)
                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.contentBackground.swiftUIStyle)
    }
}
