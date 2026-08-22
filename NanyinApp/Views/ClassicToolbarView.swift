//
//  ClassicToolbarView.swift
//  Nanyin
//

import SwiftUI

struct ClassicToolbarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    private let transportStyle = ChromeStyle(
        role: .transport,
        size: CGSize(width: 28, height: 26)
    )

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ChromeButton(
                    title: "‹",
                    accessibilityLabel: "Back",
                    style: transportStyle,
                    action: app.goBack
                )
                    .disabled(!app.canGoBack)
                    .help(app.canGoBack ? "Back" : "No navigation history")

                ChromeButton(
                    title: "›",
                    accessibilityLabel: "Forward",
                    style: transportStyle,
                    action: app.goForward
                )
                    .disabled(!app.canGoForward)
                    .help(app.canGoForward ? "Forward" : "No navigation history")
            }

            Rectangle()
                .fill(theme.colors.divider)
                .frame(width: 1, height: 18)

            ChromeSearchField(
                text: Binding(
                    get: { app.searchQuery },
                    set: { app.searchQuery = $0 }
                ),
                style: ChromeSearchStyle(
                    size: CGSize(width: 280, height: 26),
                    placeholder: "Search Nanyin",
                    focusToken: app.searchFocusToken,
                    palette: theme.chrome.palette
                ),
                onTextChange: { value in
                    app.searchQuery = value
                    if SearchView.pastedTrackLinkID(value) == nil {
                        app.searchDebounced(value)
                    }
                },
                onSubmit: { value in
                    app.searchQuery = value
                    if SearchView.pastedTrackLinkID(value) == nil {
                        app.search(value)
                    }
                    app.open(.search)
                }
            )

            Spacer(minLength: 8)

            Text("NANYIN")
                .font(theme.typography.sectionHeader)
                .tracking(1.3)
                .foregroundStyle(theme.colors.primaryText.opacity(0.86))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ChromeToolbar()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
        }
    }
}
