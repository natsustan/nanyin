//
//  LoginView.swift
//  Nanyin
//

import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: theme.id == .classic2010 ? 18 : 28) {
            if theme.id == .classic2010 {
                classicBrand
            } else {
                darkBrand
            }

            authAction

            if let error = app.authError {
                authError(error)
            }

            Text("Requires Spotify Premium. Unofficial client — not affiliated with Spotify.")
                .font(.caption2)
                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var darkBrand: some View {
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
    }

    private var classicBrand: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.quarters")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("nanyin")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text("Native Spotify client for macOS")
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding + 2)
        .background {
            ChromeSectionBar(style: ChromeSectionBarStyle(height: 56))
        }
    }

    @ViewBuilder
    private var authAction: some View {
        switch app.authState {
        case .signingIn:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(theme.colors.accent)
                Text("Complete the sign-in in your browser…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        default:
            if theme.id == .classic2010 {
                ChromeButton(
                    title: "CONNECT WITH SPOTIFY",
                    accessibilityLabel: "Connect with Spotify",
                    style: ChromeStyle(role: .pill, size: CGSize(width: 188, height: 28)),
                    action: app.signIn
                )
            } else {
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
        }
    }

    private func authError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(theme.colors.error)
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.metrics.pageHorizontalInset + 12)
            .padding(.vertical, theme.id == .classic2010 ? theme.metrics.smallPadding : 0)
            .background(theme.colors.errorContainer.swiftUIStyle)
            .overlay {
                if theme.id == .classic2010 {
                    Rectangle()
                        .stroke(theme.colors.errorBorder, lineWidth: 1)
                }
            }
    }
}
