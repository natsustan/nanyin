//
//  ClassicTitleBarControls.swift
//  Nanyin
//

import SwiftUI

struct ClassicTitleBarControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    private let transportStyle = ChromeStyle(
        role: .titlebarNavigation,
        size: CGSize(width: 22, height: 19),
        surface: .titlebarAccessory
    )

    var body: some View {
        HStack(spacing: 5) {
            ChromeButton(
                title: "",
                accessibilityLabel: "Back",
                symbolName: "arrowtriangle.left.fill",
                style: transportStyle,
                action: app.goBack
            )
            .disabled(!app.canGoBack)
            .help(app.canGoBack ? "Back" : "No navigation history")

            ChromeButton(
                title: "",
                accessibilityLabel: "Forward",
                symbolName: "arrowtriangle.right.fill",
                style: transportStyle,
                action: app.goForward
            )
            .disabled(!app.canGoForward)
            .help(app.canGoForward ? "Forward" : "No navigation history")

            ChromeSearchField(
                text: Binding(
                    get: { app.searchQuery },
                    set: { app.searchQuery = $0 }
                ),
                style: ChromeSearchStyle(
                    size: CGSize(width: 170, height: 19),
                    placeholder: "Search",
                    focusToken: app.searchFocusToken,
                    surface: .titlebarAccessory,
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(y: 5)
    }
}
