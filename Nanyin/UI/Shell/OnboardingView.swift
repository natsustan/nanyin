import AppKit
import NanyinKit
import SwiftUI

/// Classic 2010 macOS split-pane setup assistant matching Nanyin's main shell:
/// - Left charcoal rail (`Theme.sidebar`) with branding and two-step progress.
/// - Right workspace (`Theme.content`) with brushed-metal sub-bar, inset Aqua
///   form well, and a collapsible zebra-striped Spotify setup checklist.
/// - Bottom graphite bar (`Theme.graphite`) with a Network Proxy popover and
///   contextual secondary actions.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.appearsActive) private var appearsActive

    @State private var showSteps = true
    @State private var stepsInitialized = false
    @State private var showProxy = false
    @State private var copiedRedirect = false
    @State private var copiedTask: Task<Void, Never>?

    private static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!
    private static let redirectURI = OAuthGrant.webAPI(clientID: "").redirectURI
    private static let railWidth: CGFloat = 224

    private enum Stage {
        case restoring
        case account
        case playback
    }

    private var stage: Stage {
        if case .restoring = app.account.state {
            .restoring
        } else if app.needsPlaybackOnboarding {
            .playback
        } else {
            .account
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebarRail
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                mainPane
            }
            bottomBar
        }
        .background(Theme.content)
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

    // MARK: - Left Rail

    private var sidebarRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetalSubBar {
                MetalSubBarTitle(title: "Setup")
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    appIcon(size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nanyin")
                            .font(AquaFont.bold(15))
                            .foregroundStyle(Theme.text)
                        Text("Classic Spotify Client")
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.sidebarHeading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 6)

                EtchedDivider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("STEPS")
                        .font(AquaFont.bold(10))
                        .foregroundStyle(Theme.sidebarHeading)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                    stepNavRow(
                        number: 1,
                        title: "Spotify Account",
                        subtitle: accountStepSubtitle,
                        status: accountStepStatus
                    )
                    stepNavRow(
                        number: 2,
                        title: "Mac Playback",
                        subtitle: "Audio & Spotify Connect",
                        status: playbackStepStatus
                    )
                }

                Spacer(minLength: 16)

                EtchedDivider()

                Text("Unofficial Spotify client, not affiliated with Spotify. Local playback requires Spotify Premium.")
                    .font(AquaFont.regular(10.5))
                    .foregroundStyle(Theme.sidebarHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.railWidth)
        .background(Theme.sidebar)
    }

    private enum StepStatus {
        case current, completed, upcoming, loading
    }

    private var accountStepStatus: StepStatus {
        switch stage {
        case .restoring: .loading
        case .account: .current
        case .playback: .completed
        }
    }

    private var playbackStepStatus: StepStatus {
        switch stage {
        case .restoring, .account: .upcoming
        case .playback: .current
        }
    }

    private var accountStepSubtitle: String {
        if let profile = app.account.profile {
            return profile.name
        }
        if case .restoring = app.account.state {
            return "Restoring session…"
        }
        return "Library & search"
    }

    private func stepNavRow(
        number: Int,
        title: String,
        subtitle: String,
        status: StepStatus
    ) -> some View {
        let selected = status == .current
        return HStack(spacing: 9) {
            ZStack {
                switch status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.green)
                case .loading:
                    ProgressView()
                        .controlSize(.mini)
                case .current:
                    Circle()
                        .fill(Theme.sidebarSelectionText.opacity(0.16))
                        .frame(width: 18, height: 18)
                    Text("\(number)")
                        .font(AquaFont.bold(10.5))
                        .foregroundStyle(Theme.sidebarSelectionText)
                case .upcoming:
                    Circle()
                        .strokeBorder(Theme.sidebarHeading.opacity(0.6), lineWidth: 1)
                        .frame(width: 18, height: 18)
                    Text("\(number)")
                        .font(AquaFont.regular(10.5))
                        .foregroundStyle(Theme.sidebarHeading)
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(selected ? AquaFont.bold(12) : AquaFont.regular(12))
                    .foregroundStyle(
                        selected
                            ? Theme.sidebarSelectionText
                            : (status == .upcoming ? Theme.sidebarHeading : Theme.sidebarText)
                    )
                    .lineLimit(1)
                Text(subtitle)
                    .font(AquaFont.regular(10.5))
                    .foregroundStyle(
                        selected
                            ? Theme.sidebarSelectionText.opacity(0.72)
                            : Theme.sidebarHeading
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            if selected {
                Theme.sidebarSelection(active: appearsActive)
                    .hairline(.top, Theme.sidebarSelectionEdgeTop)
                    .hairline(.bottom, Theme.sidebarSelectionEdgeBottom)
            }
        }
    }

    // MARK: - Main Workspace

    private var mainPane: some View {
        VStack(spacing: 0) {
            MetalSubBar {
                switch stage {
                case .restoring:
                    MetalSubBarTitle(title: "Connecting to Spotify")
                case .account:
                    MetalSubBarTitle(title: "Spotify Account", detail: "Step 1 of 2")
                case .playback:
                    MetalSubBarTitle(title: "Enable Playback on This Mac", detail: "Step 2 of 2")
                }
                Spacer(minLength: 0)
                if stage == .playback, let profile = app.account.profile {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.metalGreen)
                        Text("\(profile.name) · Premium")
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.metalSecondaryText)
                    }
                    .padding(.trailing, 10)
                }
            }

            Group {
                switch stage {
                case .restoring:
                    restoringBody
                case .account:
                    accountBody
                case .playback:
                    playbackBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.content)
    }

    // MARK: - Restoring

    private var restoringBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to Spotify…")
                    .font(AquaFont.bold(13))
                    .foregroundStyle(Theme.text)
            }
            Text("Checking your saved session in Keychain.")
                .font(AquaFont.regular(11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(24)
    }

    // MARK: - Step 1: Spotify Account

    private var accountBody: some View {
        @Bindable var account = app.account
        let validClientID = OAuthGrant.looksLikeClientID(account.clientID)
        let showFormatHint = !account.clientID.isEmpty && !validClientID

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign In to Spotify")
                        .font(AquaFont.bold(18))
                        .foregroundStyle(Theme.text)
                    Text(
                        validClientID && !showSteps
                            ? "Authorize Nanyin in your browser using your saved Spotify Client ID."
                            : "Enter your personal Spotify Client ID, then sign in through your browser."
                    )
                    .font(AquaFont.regular(12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                switch account.state {
                case .checkingClient:
                    browserWaitWell("Checking Client ID with Spotify…", onCancel: account.cancelSignIn)

                case .waitingForBrowser(let url):
                    browserWaitWell(
                        "Waiting for Spotify in your browser…",
                        reopen: ("Open Sign-In Page Again", url),
                        hint: "If Spotify reports “Invalid redirect URI”, verify that \(Self.redirectURI) is saved verbatim in your app settings, then try again.",
                        onCancel: account.cancelSignIn
                    )

                case .loadingProfile:
                    browserWaitWell("Loading your Spotify account…", onCancel: account.cancelSignIn)

                default:
                    if case .failed(let problem, let canRetrySaved) = account.state {
                        errorBanner(problem.message, canRetrySaved: canRetrySaved)
                    }

                    insetWell {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Spotify Client ID")
                                    .font(AquaFont.bold(11.5))
                                    .foregroundStyle(Theme.sidebarText)

                                HStack(spacing: 8) {
                                    AquaTextField(
                                        text: $account.clientID,
                                        prompt: "32-character Client ID",
                                        monospaced: true,
                                        onSubmit: { if validClientID { startSignIn() } }
                                    )
                                    Button("Paste") {
                                        if let pasted = NSPasteboard.general.string(forType: .string) {
                                            account.clientID = pasted
                                        }
                                    }
                                    .buttonStyle(TexturedButtonStyle())
                                }

                                if showFormatHint {
                                    Text("A Client ID is 32 hexadecimal characters (0–9, a–f). Make sure you copied the Client ID rather than the Client Secret.")
                                        .font(AquaFont.regular(11))
                                        .foregroundStyle(Theme.hex(0xF08B7D))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            EtchedDivider()

                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.secondaryText)
                                    Text("Opens Spotify in your browser. Nanyin never sees your password.")
                                        .font(AquaFont.regular(11))
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Button("Sign In with Spotify", action: startSignIn)
                                    .buttonStyle(AquaPrimaryButtonStyle())
                                    .disabled(!validClientID)
                            }
                        }
                    }

                    setupGuideBox
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    private var setupGuideBox: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { showSteps.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: showSteps ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 11)
                    Text("First time? One-time Spotify app setup")
                        .font(AquaFont.bold(11.5))
                        .foregroundStyle(Theme.hex(0xE6E6E6))
                    Spacer(minLength: 8)
                    Text("~2 min · Premium required")
                        .font(AquaFont.regular(10.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Theme.graphite)
                .hairline(.top, Theme.graphiteHighlight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSteps {
                VStack(spacing: 0) {
                    guideRow(index: 0, number: 1) {
                        HStack(alignment: .center, spacing: 10) {
                            Text("Open the Spotify Developer Dashboard and sign in with your Premium account.")
                                .font(AquaFont.regular(12))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button {
                                openURL(Self.dashboardURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Open Dashboard")
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .buttonStyle(TexturedButtonStyle())
                        }
                    }

                    guideRow(index: 1, number: 2) {
                        Text("Click Create app, enter any app name and description, tick Web API, and accept the terms.")
                            .font(AquaFont.regular(12))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    guideRow(index: 2, number: 3) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Under Redirect URIs, add this exact address and click Save:")
                                .font(AquaFont.regular(12))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text(Self.redirectURI)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 6)
                                Button(copiedRedirect ? "Copied" : "Copy") {
                                    copyRedirectURI()
                                }
                                .buttonStyle(TexturedButtonStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.hex(0x212121)))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hex(0x161616), lineWidth: 1))
                        }
                    }

                    guideRow(index: 3, number: 4) {
                        Text("Open the app's Settings page, copy its Client ID, and paste it into the field above.")
                            .font(AquaFont.regular(12))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .hairline(.top, Theme.graphiteEdge)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hex(0x1A1A1A), lineWidth: 1))
        .background(shape.fill(.white.opacity(0.05)).offset(y: 1))
    }

    private func guideRow<Content: View>(
        index: Int,
        number: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.rowColor(index))
        .hairline(.top, index == 0 ? .clear : Theme.divider.opacity(0.65))
    }

    // MARK: - Step 2: Playback Approval

    private var playbackBody: some View {
        let session = app.session

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Enable Playback on This Mac")
                        .font(AquaFont.bold(18))
                        .foregroundStyle(Theme.text)
                    Text("One quick browser approval lets Nanyin stream audio directly on this Mac and load Made for You, New Releases, and other people's playlists.")
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch session.state {
                case .authorizing:
                    browserWaitWell(
                        "Waiting for your approval in the browser…",
                        reopen: session.authorizeURL.map { ("Open Approval Page Again", $0) },
                        hint: "Approve with the same Spotify account you just signed in with.",
                        onCancel: { session.cancelAuthorize() }
                    )

                case .connecting:
                    insetWell {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Connecting playback to Spotify…")
                                .font(AquaFont.bold(12.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }

                case .needsAuthorization(let reason), .failed(let reason):
                    VStack(alignment: .leading, spacing: 12) {
                        errorBanner(reason, canRetrySaved: false)
                        playbackActionWell(buttonTitle: "Approve Playback in Browser", action: startPlaybackApproval)
                    }

                case .waiting(let until, let reason):
                    VStack(alignment: .leading, spacing: 12) {
                        errorBanner("\(reason). Trying again \(until.formatted(.relative(presentation: .named))).", canRetrySaved: false)
                        playbackActionWell(buttonTitle: "Try Now", action: session.retry)
                    }

                default:
                    playbackActionWell(buttonTitle: "Approve Playback in Browser", action: startPlaybackApproval)
                }

                Text("You can skip this step and browse your library right away; playback can be enabled later from the notice bar at the bottom of the window.")
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
    }

    private func playbackActionWell(buttonTitle: String, action: @escaping () -> Void) -> some View {
        insetWell {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.hex(0x2F2F2F))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                    Image(systemName: "headphones")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Local Audio & Spotify Connect")
                        .font(AquaFont.bold(12.5))
                        .foregroundStyle(Theme.text)
                    Text("Reusable playback credential stored in your macOS Keychain.")
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Button(buttonTitle, action: action)
                    .buttonStyle(AquaPrimaryButtonStyle())
            }
        }
    }

    // MARK: - Bottom Graphite Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                showProxy.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(proxyIconTint)
                    Text(proxyButtonLabel)
                    if app.proxy.errorMessage != nil || app.proxy.hasPendingManualChanges {
                        Circle()
                            .fill(app.proxy.errorMessage != nil ? Theme.hex(0xF08B7D) : Theme.hex(0xE8C26A))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(GraphiteActionButtonStyle())
            .popover(isPresented: $showProxy, arrowEdge: .top) {
                VStack(spacing: 0) {
                    GraphiteHeader {
                        Image(systemName: "network")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Network Proxy")
                    }
                    ProxySettingsForm()
                        .padding(14)
                }
                .frame(width: 350)
                .background(Theme.content)
                .preferredColorScheme(.dark)
            }

            Spacer()

            switch stage {
            case .restoring:
                EmptyView()

            case .account:
                if !appVersion.isEmpty {
                    Text("Nanyin \(appVersion)")
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                }

            case .playback:
                Button("Sign Out") {
                    Task { await app.signOut() }
                }
                .buttonStyle(TexturedButtonStyle())

                Button("Skip for Now") {
                    app.skipPlaybackSetup()
                }
                .buttonStyle(TexturedButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.graphite)
        .hairline(.top, Theme.graphiteHighlight)
        .padding(.top, 1)
        .hairline(.top, Theme.graphiteEdge)
    }

    private var proxyButtonLabel: String {
        if app.proxy.errorMessage != nil {
            return "Proxy Error…"
        }
        return "Proxy: \(app.proxy.mode.label)…"
    }

    private var proxyIconTint: Color {
        if app.proxy.errorMessage != nil {
            Theme.hex(0xF08B7D)
        } else if app.proxy.mode.isManual {
            Theme.green
        } else {
            Theme.text
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: - Shared Wells & Controls

    private func insetWell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.hex(0x232323)))
            .overlay(shape.strokeBorder(Theme.hex(0x171717), lineWidth: 1))
            .background(shape.fill(.white.opacity(0.06)).offset(y: 1))
    }

    private func browserWaitWell(
        _ label: String,
        reopen: (title: String, url: URL)? = nil,
        hint: String? = nil,
        onCancel: @escaping @MainActor () -> Void
    ) -> some View {
        insetWell {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(label)
                        .font(AquaFont.bold(13))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(TexturedButtonStyle())
                }

                if let hint {
                    Text(hint)
                        .font(AquaFont.regular(11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let reopen {
                    Button(reopen.title) { openURL(reopen.url) }
                        .buttonStyle(TexturedButtonStyle())
                }
            }
        }
    }

    private func errorBanner(_ message: String, canRetrySaved: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.hex(0xF2B96E))
                .padding(.top, 1)
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
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x473322)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hex(0x8C6438), lineWidth: 1))
    }

    private func appIcon(size: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private func startSignIn() {
        guard app.proxy.applyPendingIfNeeded() else {
            showProxy = true
            return
        }
        app.account.signIn()
    }

    private func startPlaybackApproval() {
        guard app.proxy.applyPendingIfNeeded() else {
            showProxy = true
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
