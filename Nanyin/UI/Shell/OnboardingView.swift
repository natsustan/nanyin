import NanyinKit
import SwiftUI

/// Sign-in: Nanyin talks to the Web API through the listener's own Spotify
/// app, so the first step is registering one.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var account = app.account
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to Spotify")
                .font(AquaFont.bold(18))
            Text("Nanyin uses your own Spotify app registration, so its requests have a quota of their own. It takes about two minutes, with a Premium account:")
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Open the Spotify developer dashboard and click Create app.")
                step(2, "Add the redirect URI  http://127.0.0.1:8989/login  and tick Web API.")
                step(3, "Copy the app's Client ID and paste it below.")
            }
            Button("Open Developer Dashboard") {
                openURL(URL(string: "https://developer.spotify.com/dashboard")!)
            }
            .buttonStyle(TexturedButtonStyle())
            HStack(spacing: 8) {
                AquaSearchField(text: $account.clientID, prompt: "Client ID", icon: nil, onSubmit: account.signIn)
                    .frame(width: 280)
                switch account.state {
                case .signingIn, .loadingProfile:
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: account.cancelSignIn)
                        .buttonStyle(TexturedButtonStyle())
                default:
                    Button("Sign In with Spotify", action: account.signIn)
                        .buttonStyle(TexturedButtonStyle())
                        .disabled(!OAuthGrant.looksLikeClientID(account.clientID))
                }
            }
            switch account.state {
            case .signingIn:
                note("Approve Nanyin in your browser. If Spotify shows “INVALID_CLIENT: Invalid redirect URI”, check the redirect URI in your app's settings.")
            case .failed(let message):
                note(message)
                Button("Retry Saved Sign-In") { Task { await account.restore() } }
                    .buttonStyle(.link)
                    .font(AquaFont.regular(11))
            default:
                EmptyView()
            }
            Text("Nanyin is an unofficial client and is not affiliated with Spotify. Playback requires Spotify Premium.")
                .font(AquaFont.regular(10))
                .foregroundStyle(Theme.secondaryText.opacity(0.8))
                .padding(.top, 8)
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: 520, alignment: .leading)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(AquaFont.bold(10))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.green))
                .foregroundStyle(.black)
            Text(text).font(AquaFont.regular(12))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AquaFont.regular(11))
            .foregroundStyle(Theme.hex(0xE8C26A))
            .fixedSize(horizontal: false, vertical: true)
    }
}
