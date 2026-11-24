import NanyinKit
import SwiftUI

/// Standard macOS Settings window (`⌘,`) for playback quality, Connect device
/// name, network proxy, cache management, and diagnostics.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTab: Tab = .playback

    enum Tab: String, CaseIterable, Identifiable {
        case playback = "Playback"
        case network = "Network"
        case storage = "Storage & Logs"

        var id: Self { self }

        var icon: String {
            switch self {
            case .playback: "speaker.wave.2"
            case .network: "network"
            case .storage: "internaldrive"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case .playback: playbackPane
                    case .network: networkPane
                    case .storage: storagePane
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.content)
        }
        .frame(width: 470, height: 340)
        .preferredColorScheme(.dark)
        .onAppear { app.settings.refreshCacheSize() }
        .onDisappear {
            app.settings.discardTransientState()
            app.proxy.discardUnsavedChanges()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                    if tab == .storage { app.settings.refreshCacheSize() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                    }
                }
                .buttonStyle(DarkSegmentButtonStyle(selected: selectedTab == tab))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.graphite)
        .hairline(.bottom, Theme.graphiteEdge)
    }

    // MARK: - Playback

    private var playbackPane: some View {
        @Bindable var settings = app.settings
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("Audio Quality")
                HStack(spacing: 6) {
                    ForEach(PlaybackSettings.AudioQuality.allCases) { quality in
                        Button(quality.shortLabel) {
                            settings.audioQuality = quality
                        }
                        .buttonStyle(DarkSegmentButtonStyle(selected: settings.audioQuality == quality))
                    }
                }
                sectionNote("Higher bitrates sound clearer and use more bandwidth and cache. Reconnects playback when changed.")
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $settings.normalizeVolume) {
                    Text("Normalize volume")
                        .font(AquaFont.bold(12))
                        .foregroundStyle(Theme.text)
                }
                .toggleStyle(.checkbox)
                sectionNote("Keep loudness more consistent across albums and playlists.")
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("Spotify Connect Device Name")
                HStack(spacing: 8) {
                    AquaTextField(
                        text: $settings.deviceNameDraft,
                        prompt: PlaybackSettings.defaultDeviceName,
                        onSubmit: { settings.applyDeviceName() }
                    )
                    Button("Apply") { settings.applyDeviceName() }
                        .buttonStyle(TexturedButtonStyle())
                        .disabled(!settings.hasPendingDeviceNameChange)
                }
                sectionNote("Shown as “\(settings.effectiveDeviceName)” in other Spotify apps. Leave blank for the default name.")
            }
        }
    }

    // MARK: - Network

    private var networkPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Proxy")
            sectionNote("Configure how Nanyin connects to Spotify. Passwords are stored in your macOS Keychain.")
            ProxySettingsForm()
        }
    }

    // MARK: - Storage & Logs

    private var storagePane: some View {
        let settings = app.settings
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("Audio & Cover Cache")
                HStack(spacing: 10) {
                    Text("Cached audio: \(settings.formattedCacheSize)")
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button(settings.isClearingCache ? "Clearing…" : "Clear Cache") {
                        settings.clearCache()
                    }
                    .buttonStyle(TexturedButtonStyle())
                    .disabled(settings.isClearingCache)
                }
                sectionNote("Nanyin caches up to 1 GB of recent audio and 512 MB of cover art locally.")
                if let status = settings.cacheStatusMessage {
                    Text(status)
                        .font(AquaFont.regular(11.5))
                        .foregroundStyle(settings.cacheStatusIsError ? Theme.hex(0xF08B7D) : Theme.green)
                }
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("Diagnostics")
                HStack(spacing: 10) {
                    Text(PlaybackEngine.logURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") { settings.revealLogs() }
                        .buttonStyle(TexturedButtonStyle())
                }
                sectionNote("Core playback logs rotate automatically at 5 MB and never include your password.")
            }

            Divider().overlay(Theme.divider)

            HStack {
                Text("Nanyin \(appVersion)")
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("Unofficial Spotify client")
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(AquaFont.bold(12))
            .foregroundStyle(Theme.text)
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(AquaFont.regular(11))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
