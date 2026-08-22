//
//  NanyinDarkShell.swift
//  Nanyin
//

import SwiftUI

/// Stable content owner shared by both shell adapters. Keeping this view at a
/// fixed identity prevents theme changes from recreating page Lists, player
/// position state, or locally focused controls.
struct AuthenticatedShell: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ShellContent()
            .modifier(
                ShellPresentationModifier(
                    kind: theme.id == .classic2010
                        ? Classic2010Shell.kind
                        : NanyinDarkShell.kind
                )
            )
    }
}

enum ShellPresentationKind {
    case nanyinDark
    case classic2010
}

protocol ShellAdapter {
    static var kind: ShellPresentationKind { get }
}

private struct ShellPresentationModifier: ViewModifier {
    let kind: ShellPresentationKind

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Group {
                if kind == .classic2010 {
                    ClassicToolbarView()
                } else {
                    Color.clear
                }
            }
            .frame(height: kind == .classic2010 ? 38 : 0)
            content
        }
        .toolbar {
            if kind == .nanyinDark {
                ToolbarItemGroup(placement: .navigation) {
                    NavigationButton(
                        systemImage: "chevron.left",
                        help: "Back",
                        enabled: app.canGoBack,
                        action: app.goBack
                    )
                    NavigationButton(
                        systemImage: "chevron.right",
                        help: "Forward",
                        enabled: app.canGoForward,
                        action: app.goForward
                    )
                }
            }
        }
    }

    @Environment(AppModel.self) private var app
}

/// Common geometry keeps AppContentView and PlayerBar stable across theme
/// changes. The presentation argument is a shell-owned structural choice;
/// source-list data and actions remain in SidebarView.
private struct ShellContent: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(
                    presentation: theme.id == .classic2010 ? .classic2010 : .nanyinDark
                )
                .frame(width: theme.metrics.sidebarWidth)

                Divider().overlay(theme.colors.playerBackground.swiftUIStyle)

                AppContentView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().overlay(theme.colors.playerBackground.swiftUIStyle)

            PlayerBar()
                .frame(height: theme.metrics.playerBarHeight)
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
        .ignoresSafeArea()
    }
}

/// Nanyin Dark's original titlebar navigation remains a native toolbar.
enum NanyinDarkShell: ShellAdapter {
    static let kind = ShellPresentationKind.nanyinDark
}

private struct NavigationButton: View {
    let systemImage: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(theme.typography.controlLabel)
                .foregroundStyle(
                    enabled
                        ? (hovering ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.85))
                        : theme.colors.disabledText
                )
                .frame(width: 28, height: 28)
                .background(
                    hovering && enabled
                        ? theme.colors.controlHover.swiftUIStyle
                        : AnyShapeStyle(Color.clear),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? help : "No navigation history")
    }
}
