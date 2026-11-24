import NanyinKit
import SwiftUI

/// Inline proxy configuration form used both on the sign-in screen (collapsible)
/// and inside the Settings window (`SettingsView`).
struct ProxySettingsForm: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var proxy = app.proxy
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(ProxyMode.allCases, id: \.self) { mode in
                    Button(mode.label) {
                        proxy.selectMode(mode)
                    }
                    .buttonStyle(DarkSegmentButtonStyle(selected: proxy.mode == mode))
                }
            }

            if proxy.mode.isManual {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        fieldLabel("Host")
                        AquaTextField(text: $proxy.host, prompt: "127.0.0.1", monospaced: true, onSubmit: { proxy.apply() })
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        fieldLabel("Port")
                        AquaTextField(text: $proxy.port, prompt: proxy.mode == .http ? "7890" : "1080", monospaced: true, onSubmit: { proxy.apply() })
                            .frame(width: 82)
                    }
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        fieldLabel("Username (optional)")
                        AquaTextField(text: $proxy.username, prompt: "Optional", onSubmit: { proxy.apply() })
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        fieldLabel("Password (optional)")
                        AquaTextField(text: $proxy.password, prompt: "Optional", isSecure: true, onSubmit: { proxy.apply() })
                    }
                }

                Text(scopeNote(for: proxy.mode, hasAuth: !proxy.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !proxy.password.isEmpty))
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Apply Proxy") {
                        proxy.apply()
                    }
                    .buttonStyle(TexturedButtonStyle())

                    if proxy.hasPendingManualChanges {
                        Text("Unsaved changes")
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.hex(0xE8C26A))
                    }
                }
            } else {
                Text(proxy.mode == .system
                    ? "Browsing and sign-in follow macOS System Proxy settings; playback connects directly unless an HTTP proxy without a password is set."
                    : "Browsing, sign-in, and playback connect directly, ignoring macOS System Proxy settings.")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = proxy.errorMessage {
                Text(error)
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.hex(0xF08B7D))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let status = proxy.statusMessage {
                Text(status)
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.green)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(AquaFont.regular(11))
            .foregroundStyle(Theme.secondaryText)
    }

    private func scopeNote(for mode: ProxyMode, hasAuth: Bool) -> String {
        if mode == .http && !hasAuth {
            "Used for sign-in, library, artwork, and playback on this Mac. Your browser uses its own proxy settings."
        } else {
            "Used for sign-in, library, and artwork. Playback on this Mac only tunnels through HTTP proxies without a password."
        }
    }
}
