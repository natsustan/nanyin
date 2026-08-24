//
//  ClassicShellGeometryFixture.swift
//  Nanyin
//

import SwiftUI

/// Offline shell envelope fixture. It deliberately uses static content so
/// geometry can be checked without AppModel, Keychain, or Spotify traffic.
struct ClassicShellGeometryFixture: View {
    let canvasSize: CGSize
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HStack(spacing: 0) {
                sidebar
                    .frame(width: theme.metrics.sidebarWidth)

                Rectangle()
                    .fill(theme.colors.divider)
                    .frame(width: 1)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Rectangle()
                .fill(theme.colors.divider)
                .frame(height: 1)

            deck
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .background(theme.colors.contentBackground.swiftUIStyle)
        .environment(\.appTheme, .classic2010)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ChromeButton(title: "‹", accessibilityLabel: "Back")
                .disabled(true)
            ChromeButton(title: "›", accessibilityLabel: "Forward")
                .disabled(true)
            ChromeSearchField(
                text: .constant(""),
                style: ChromeSearchStyle(size: CGSize(width: 280, height: 26))
            )
            Spacer()
            Text("NANYIN")
                .font(theme.typography.sectionHeader)
                .tracking(1.2)
                .foregroundStyle(theme.colors.primaryText)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ChromeToolbar() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(12)
            ForEach(["Home", "Search", "Songs", "Albums"], id: \.self) { title in
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.colors.secondaryText)
                        .frame(width: 5, height: 5)
                    Text(title)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            Spacer()
            HStack(spacing: 8) {
                Rectangle()
                    .fill(theme.colors.placeholderBackground.swiftUIStyle)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current track title")
                        .font(theme.typography.playerTitle)
                        .lineLimit(1)
                    Text("Artist · Album")
                        .font(theme.typography.compact)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .background(theme.colors.sidebarBackground.swiftUIStyle)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Home")
                .font(theme.typography.pageTitle)
                .foregroundStyle(theme.colors.primaryText)
                .padding(20)
            HStack(spacing: 0) {
                ForEach(["Track", "Artist", "Album", "Time"], id: \.self) { title in
                    Text(title)
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(theme.colors.raisedSurface.swiftUIStyle)
            ForEach(0..<8, id: \.self) { index in
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .frame(width: 30, alignment: .leading)
                    Text("A long example track title")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Artist Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Album Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("3:42")
                        .frame(width: 42, alignment: .trailing)
                }
                .font(theme.typography.metadata)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 16)
                .frame(height: theme.metrics.compactRowHeight)
            }
            Spacer()
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var deck: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Previous track",
                    symbolName: "backward.fill",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24))
                )
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Play",
                    symbolName: "play.fill",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 28, height: 28))
                )
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Next track",
                    symbolName: "forward.fill",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24))
                )
                Spacer(minLength: 6)
                Capsule()
                    .fill(theme.colors.sliderTrack)
                    .frame(width: 68, height: 4)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(width: theme.metrics.sidebarWidth)
            Rectangle()
                .fill(theme.colors.border)
                .frame(width: 1)
            HStack(spacing: 8) {
                Text("0:00")
                    .font(theme.typography.mono)
                    .frame(width: 34, alignment: .trailing)
                ChromeSliderTrack(
                    style: ChromeSliderStyle(size: CGSize(width: 220, height: 10), fraction: 0.42),
                    fillsAvailableWidth: true
                )
                Text("3:42")
                    .font(theme.typography.mono)
                    .frame(width: 34, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            Rectangle()
                .fill(theme.colors.border)
                .frame(width: 1)
            ForEach(["shuffle", "repeat", "list.bullet"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 40, height: theme.metrics.playerBarHeight)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(theme.colors.border.opacity(0.65))
                            .frame(width: 1)
                    }
            }
        }
        .frame(height: theme.metrics.playerBarHeight)
        .background { ChromeSectionBar(style: ChromeSectionBarStyle(height: theme.metrics.playerBarHeight)) }
    }
}

#Preview("Classic 900x600") {
    ClassicShellGeometryFixture(canvasSize: CGSize(width: 900, height: 600))
        .environment(\.appTheme, .classic2010)
}

#Preview("Classic 1280x800") {
    ClassicShellGeometryFixture(canvasSize: CGSize(width: 1280, height: 800))
        .environment(\.appTheme, .classic2010)
}

#Preview("Classic wide desktop") {
    ClassicShellGeometryFixture(canvasSize: CGSize(width: 1600, height: 900))
        .environment(\.appTheme, .classic2010)
}
