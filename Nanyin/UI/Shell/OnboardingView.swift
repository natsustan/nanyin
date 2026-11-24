import AppKit
import NanyinKit
import SwiftUI

/// Onboarding & sign-in shell:
/// - `.restoring`: quiet connecting card at launch (no flash of the setup form).
/// - Step 1: Web API sign-in with the listener's own Spotify Client ID (two-column
///   setup card for first-time / refused sign-ins; compact single-column card for
///   returning listeners who already have a valid Client ID saved).
/// - Step 2: Optional guided one-time playback approval for Premium accounts so
///   audio streaming, What's New, and other people's playlists work immediately.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var showSteps = true
    @State private var stepsInitialized = false
    @State private var showProxy = false
    @State private var copiedRedirect = false
    @State private var copiedTask: Task<Void, Never>?

    private static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!
    private static let redirectURI = OAuthGrant.webAPI(clientID: "").redirectURI

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    Spacer(minLength: 16)

                    Group {
                        if case .restoring = app.account.state {
                            restoringCard
                        } else if app.needsPlaybackOnboarding {
                            playbackStepCard
                        } else {
                            webAPISignInCard
                        }
                    }

                    Text("Nanyin is an unofficial client and is not affiliated with Spotify. Playback requires Spotify Premium.")
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
                .padding(.horizontal, 24)
            }
        }
        .background(
            LinearGradient(
                colors: [Theme.hex(0x323232), Theme.content],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            if !stepsInitialized {
                stepsInitialized = true
                showSteps = !OAuthGrant.looksLikeClientID(app.account.clientID) || problemNeedsSteps
            }
        }
        .onChange(of: app.account.state) { _, newState in
            if case .failed(let problem, _) = newState, problem.needsSetupGuidance {
                showSteps = true
            }
        }
    }

    private var problemNeedsSteps: Bool {
        if case .failed(let problem, _) = app.account.state {
            return problem.needsSetupGuidance
        }
        return false
    }

    // MARK: - Restoring

    private var restoringCard: some View {
        cardContainer(width: 360) {
            VStack(spacing: 14) {
                appIcon(size: 56)
                Text("Nanyin")
                    .font(AquaFont.bold(18))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to Spotify…")
                        .font(AquaFont.regular(13))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Step 1: Web API Sign-In

    private var webAPISignInCard: some View {
        let waiting = app.account.isBusy
        let twoColumn = !waiting && showSteps
        return cardContainer(width: twoColumn ? 730 : 410) {
            if twoColumn {
                HStack(alignment: .top, spacing: 26) {
                    signInColumn(compact: false)
                        .frame(width: 310)
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 1)
                    setupStepsColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                signInColumn(compact: true)
            }
        }
    }

    private func signInColumn(compact: Bool) -> some View {
        @Bindable var account = app.account
        let validClientID = OAuthGrant.looksLikeClientID(account.clientID)
        let showFormatHint = !account.clientID.isEmpty && !validClientID

        return VStack(alignment: compact ? .center : .leading, spacing: 12) {
            VStack(alignment: compact ? .center : .leading, spacing: 6) {
                appIcon(size: compact ? 56 : 48)
                Text("Sign in to Spotify")
                    .font(AquaFont.bold(compact ? 19 : 17))
                    .foregroundStyle(Theme.text)
                if !account.isBusy {
                    Text(compact
                        ? "Sign in through your browser with your saved Spotify Client ID."
                        : "Step 1 of 2 · Library & Search")
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(compact ? .center : .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)

            switch account.state {
            case .checkingClient:
                browserWaitBlock("Checking Client ID with Spotify…", onCancel: account.cancelSignIn)
            case .waitingForBrowser(let url):
                browserWaitBlock(
                    "Waiting for Spotify in your browser…",
                    reopen: ("Didn't open? Open Sign-In Page Again", url),
                    hint: "If Spotify shows “Invalid redirect URI”, verify that \(Self.redirectURI) is added exactly in your app settings, save, and sign in again.",
                    onCancel: account.cancelSignIn
                )
            case .loadingProfile:
                browserWaitBlock("Loading your Spotify account…", onCancel: account.cancelSignIn)
            default:
                if case .failed(let problem, let canRetrySaved) = account.state {
                    errorBox(problem.message, canRetrySaved: canRetrySaved)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Spotify Client ID")
                            .font(AquaFont.bold(11.5))
                            .foregroundStyle(Theme.sidebarText)
                        Spacer()
                        Button("Paste") {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                account.clientID = pasted
                            }
                        }
                        .buttonStyle(.link)
                        .font(AquaFont.regular(11.5))
                        .foregroundStyle(Theme.green)
                    }
                    AquaTextField(
                        text: $account.clientID,
                        prompt: "32-character Client ID",
                        monospaced: true,
                        onSubmit: { if validClientID { startSignIn() } }
                    )
                    if showFormatHint {
                        Text("A Client ID is 32 hexadecimal characters (0–9, a–f). Make sure you copied the Client ID, not the Client Secret.")
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.hex(0xF08B7D))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)

                Button("Sign In with Spotify", action: startSignIn)
                    .buttonStyle(AquaPrimaryButtonStyle(fullWidth: true))
                    .disabled(!validClientID)
                    .padding(.top, 2)

                Text("Opens Spotify in your browser. Nanyin never sees your password.")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(compact ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)

                HStack(spacing: 14) {
                    if !showSteps {
                        Button("How to register Nanyin") {
                            withAnimation(.easeInOut(duration: 0.16)) { showSteps = true }
                        }
                        .buttonStyle(.link)
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.sidebarText)
                    }
                    proxyToggleButton
                }
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .padding(.top, 2)

                if showProxy {
                    proxyPanel
                }
            }
        }
    }

    private func browserWaitBlock(
        _ label: String,
        reopen: (title: String, url: URL)? = nil,
        hint: String? = nil,
        onCancel: @escaping @MainActor () -> Void
    ) -> some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label)
                    .font(AquaFont.bold(12.5))
                    .foregroundStyle(Theme.text)
            }
            .padding(.top, 4)

            if let reopen {
                Button(reopen.title) { openURL(reopen.url) }
                    .buttonStyle(.link)
                    .font(AquaFont.regular(12))
                    .foregroundStyle(Theme.green)
            }

            if let hint {
                Text(hint)
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x272727)))
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(TexturedButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var proxyToggleButton: some View {
        Button(showProxy ? "Hide Proxy Settings" : "Proxy Settings") {
            withAnimation(.easeInOut(duration: 0.16)) { showProxy.toggle() }
        }
        .buttonStyle(.link)
        .font(AquaFont.regular(12))
        .foregroundStyle(app.proxy.errorMessage != nil ? Theme.hex(0xF08B7D) : Theme.secondaryText)
    }

    private func errorBox(_ message: String, canRetrySaved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.hex(0xFAD2A0))
                .fixedSize(horizontal: false, vertical: true)
            if canRetrySaved {
                Button("Retry Saved Sign-In", action: app.account.retrySavedSignIn)
                    .buttonStyle(TexturedButtonStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x473322)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hex(0x8C6438), lineWidth: 1))
    }

    private var setupStepsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Register Nanyin with Spotify")
                    .font(AquaFont.bold(15))
                    .foregroundStyle(Theme.text)
                Spacer()
                if OAuthGrant.looksLikeClientID(app.account.clientID) {
                    Button("Hide") {
                        withAnimation(.easeInOut(duration: 0.16)) { showSteps = false }
                    }
                    .buttonStyle(.link)
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText)
                }
            }

            Text("Spotify asks each listener to register a personal app once (on a Premium account). It takes about two minutes and gives Nanyin its own quota.")
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(1, "Open Spotify's Developer Dashboard and sign in.") {
                    Button {
                        openURL(Self.dashboardURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text("developer.spotify.com/dashboard")
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.link)
                    .font(AquaFont.bold(12))
                    .foregroundStyle(Theme.green)
                }

                stepRow(2, "Click Create app. Any app name and description will do.") {}

                stepRow(3, "Under Redirect URIs, add exactly:") {
                    HStack(spacing: 6) {
                        Text(Self.redirectURI)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button(copiedRedirect ? "Copied" : "Copy") {
                            copyRedirectURI()
                        }
                        .buttonStyle(TexturedButtonStyle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.hex(0x242424)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hex(0x1A1A1A), lineWidth: 1))
                }

                stepRow(4, "Tick Web API, accept the terms, and click Save.") {}

                stepRow(5, "Copy the Client ID from your app's Settings page and paste it on the left.") {}
            }
            .padding(.top, 2)
        }
    }

    private var proxyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.divider)
            ProxySettingsForm()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x282828)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.divider, lineWidth: 1))
    }

    // MARK: - Step 2: Playback Approval

    private var playbackStepCard: some View {
        let session = app.session
        let profile = app.account.profile

        return cardContainer(width: 450) {
            VStack(spacing: 14) {
                stepProgress(current: 2, total: 2)

                ZStack {
                    Circle()
                        .fill(Theme.green.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "headphones")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }

                VStack(spacing: 6) {
                    Text("Enable Playback on This Mac")
                        .font(AquaFont.bold(18))
                        .foregroundStyle(Theme.text)
                    Text("One more quick browser approval lets Nanyin play audio on this Mac and load Made for You, New Releases, and other people's playlists.")
                        .font(AquaFont.regular(12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let profile {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                            .font(.system(size: 12))
                        Text("Signed in as \(profile.name) · Premium")
                            .font(AquaFont.regular(12))
                            .foregroundStyle(Theme.sidebarText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.hex(0x262626)))
                    .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                }

                switch session.state {
                case .authorizing:
                    browserWaitBlock(
                        "Waiting for your approval in the browser…",
                        reopen: session.authorizeURL.map { ("Didn't open? Open Approval Page Again", $0) },
                        hint: "Make sure you approve with the same Spotify account you just signed in with.",
                        onCancel: { session.cancelAuthorize() }
                    )

                case .connecting:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting playback to Spotify…")
                            .font(AquaFont.bold(12.5))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 8)

                case .needsAuthorization(let reason), .failed(let reason):
                    VStack(spacing: 10) {
                        errorBox(reason, canRetrySaved: false)
                        Button("Approve Playback in Browser", action: startPlaybackApproval)
                            .buttonStyle(AquaPrimaryButtonStyle(fullWidth: true))
                    }

                case .waiting(let until, let reason):
                    VStack(spacing: 10) {
                        errorBox("\(reason). Trying again \(until.formatted(.relative(presentation: .named))).", canRetrySaved: false)
                        Button("Try Now", action: session.retry)
                            .buttonStyle(AquaPrimaryButtonStyle(fullWidth: true))
                    }

                default:
                    Button("Approve Playback in Browser", action: startPlaybackApproval)
                        .buttonStyle(AquaPrimaryButtonStyle(fullWidth: true))
                        .padding(.top, 4)
                }

                HStack(spacing: 18) {
                    Button("Skip for now") {
                        app.skipPlaybackSetup()
                    }
                    .buttonStyle(.link)
                    .font(AquaFont.regular(12))
                    .foregroundStyle(Theme.sidebarText)

                    proxyToggleButton

                    Button("Sign Out") {
                        Task { await app.signOut() }
                    }
                    .buttonStyle(.link)
                    .font(AquaFont.regular(12))
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 2)

                if showProxy {
                    proxyPanel
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func cardContainer<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(28)
            .frame(maxWidth: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.hex(0x333333))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.hex(0x1C1C1C), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .padding(.top, 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }

    private func appIcon(size: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private func stepProgress(current: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1 ... total, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? Theme.green : Theme.hex(0x4E4E4E))
                        .frame(width: 40, height: 4)
                }
            }
            Text("Step \(current) of \(total)")
                .font(AquaFont.regular(11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func stepRow<Extra: View>(
        _ number: Int,
        _ text: String,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(AquaFont.bold(11))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.green.opacity(0.22)))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(AquaFont.regular(12.5))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }

    private func startSignIn() {
        guard app.proxy.applyPendingIfNeeded() else {
            withAnimation(.easeInOut(duration: 0.16)) { showProxy = true }
            return
        }
        app.account.signIn()
    }

    private func startPlaybackApproval() {
        guard app.proxy.applyPendingIfNeeded() else {
            withAnimation(.easeInOut(duration: 0.16)) { showProxy = true }
            return
        }
        app.session.authorize()
    }

    private func copyRedirectURI() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.redirectURI, forType: .string)
        copiedRedirect = true
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copiedRedirect = false
        }
    }
}
