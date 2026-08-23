//
//  ClassicTitleBarControls.swift
//  Nanyin
//

import SwiftUI

struct ClassicTitleBarControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Back",
                    symbolName: "arrowtriangle.left.fill",
                    style: navigationStyle(position: .leading),
                    action: app.goBack
                )
                .disabled(!app.canGoBack)
                .help(app.canGoBack ? "Back" : "No navigation history")
                .zIndex(1)

                ChromeButton(
                    title: "",
                    accessibilityLabel: "Forward",
                    symbolName: "arrowtriangle.right.fill",
                    style: navigationStyle(position: .trailing),
                    action: app.goForward
                )
                .disabled(!app.canGoForward)
                .help(app.canGoForward ? "Forward" : "No navigation history")
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.black.opacity(0.40), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.01))
                    .shadow(color: .black.opacity(0.30), radius: 1, y: 1)
                    .shadow(color: .white.opacity(0.45), radius: 0, y: 1)
            }

            ChromeSearchField(
                text: Binding(
                    get: { app.searchQuery },
                    set: { app.searchQuery = $0 }
                ),
                style: ChromeSearchStyle(
                    size: CGSize(width: 230, height: 20),
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
        .offset(y: 4)
    }

    private func navigationStyle(position: ChromeSegmentPosition) -> ChromeStyle {
        ChromeStyle(
            role: .titlebarNavigation,
            size: CGSize(width: 25, height: 20),
            surface: .titlebarAccessory,
            segmentPosition: position
        )
    }
}
