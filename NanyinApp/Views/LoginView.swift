//
//  LoginView.swift
//  Nanyin
//

import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "music.note.quarters")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("nanyin")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("Native Spotify client for macOS")
                    .foregroundStyle(Theme.textSecondary)
            }

            switch app.authState {
            case .signingIn:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Complete the sign-in in your browser…")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
            default:
                Button {
                    app.signIn()
                } label: {
                    Text("CONNECT WITH SPOTIFY")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .cornerRadius(24)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            if let error = app.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Text("Requires Spotify Premium. Unofficial client — not affiliated with Spotify.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
