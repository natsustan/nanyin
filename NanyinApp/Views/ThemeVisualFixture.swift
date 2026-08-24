//
//  ThemeVisualFixture.swift
//  Nanyin
//

import SwiftUI

/// Static states used by the offline visual calibration matrix. This fixture
/// deliberately contains no runtime model, artwork loader, credentials, or
/// network client so previews can be inspected without live session effects.
enum ThemeFixtureState: String, CaseIterable, Identifiable {
    case defaultState = "Default"
    case hovered = "Hovered"
    case pressed = "Pressed"
    case disabled = "Disabled"
    case selected = "Selected"
    case current = "Current"
    case empty = "Empty"
    case loading = "Loading"
    case error = "Error"
    case longText = "Long text"

    var id: String { rawValue }
}

/// Offline reference envelope for the shell, source list, track table, player
/// deck, and state-specific content. It is a geometry and hierarchy reference,
/// not a production screen and must stay independent from live app state.
struct ThemeVisualFixture: View {
    let themeID: AppThemeID
    let state: ThemeFixtureState
    let canvasSize: CGSize

    private var theme: AppTheme { AppTheme.resolve(themeID) }
    private var isClassic: Bool { themeID == .classic2010 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HStack(spacing: 0) {
                sourceList
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

            player
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .background(theme.colors.contentBackground.swiftUIStyle)
        .environment(\.appTheme, theme)
    }

    @ViewBuilder
    private var toolbar: some View {
        if isClassic {
            HStack(spacing: 8) {
                ChromeButton(title: "‹", accessibilityLabel: "Back")
                    .disabled(state == .disabled)
                ChromeButton(title: "›", accessibilityLabel: "Forward")
                    .disabled(state == .disabled)
                ChromeSearchField(
                    text: .constant(state == .longText ? "A very long search query" : ""),
                    style: ChromeSearchStyle(size: CGSize(width: 260, height: 26))
                )
                Spacer(minLength: 8)
                Text("NANYIN")
                    .font(theme.typography.sectionHeader)
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.primaryText)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ChromeToolbar() }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.colors.border)
                    .frame(height: 1)
            }
        } else {
            HStack(spacing: 8) {
                Button("‹") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.primaryText)
                    .help("Back")
                Button("›") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.primaryText)
                    .help("Forward")
                TextField("Search Nanyin", text: .constant(state == .longText ? "A very long search query" : ""))
                    .textFieldStyle(.roundedBorder)
                    .tint(theme.colors.accent)
                    .frame(width: 260)
                Spacer(minLength: 8)
                Text("NANYIN")
                    .font(theme.typography.sectionHeader)
                    .foregroundStyle(theme.colors.primaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(theme.colors.raisedSurface.swiftUIStyle)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.colors.divider)
                    .frame(height: 1)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.vertical, theme.metrics.smallPadding + 2)

            ForEach(["Home", "Search", "Queue", "Liked Songs", "Saved Albums"], id: \.self) { item in
                let selected = state == .selected && item == "Search"
                HStack(spacing: 8) {
                    Circle()
                        .fill(selected ? theme.colors.focusRing : theme.colors.secondaryText)
                        .frame(width: 5, height: 5)
                    Text(item)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.vertical, theme.metrics.smallPadding - 1)
                .background(selected ? theme.colors.rowSelected.swiftUIStyle : AnyShapeStyle(Color.clear))
                .overlay(alignment: .leading) {
                    if selected {
                        Rectangle()
                            .fill(theme.colors.focusRing)
                            .frame(width: 2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Rectangle()
                    .fill(theme.colors.placeholderBackground.swiftUIStyle)
                    .frame(width: isClassic ? 56 : 64, height: isClassic ? 56 : 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state == .longText ? "A very long current track title" : "Current track title")
                        .font(theme.typography.playerTitle)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    Text("Artist · Album")
                        .font(theme.typography.compact)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(theme.metrics.sidebarInset)
        }
        .background(theme.colors.sidebarBackground.swiftUIStyle)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(state == .longText ? "A very long playlist title" : "Home")
                    .font(theme.typography.pageTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(state.rawValue)
                    .font(theme.typography.compact)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(.horizontal, theme.metrics.pageHorizontalInset)
            .padding(.vertical, theme.metrics.smallPadding + 4)

            switch state {
            case .empty:
                statePanel(icon: "music.note", title: "Nothing here yet", detail: "Empty content state")
            case .loading:
                statePanel(icon: "hourglass", title: "Loading…", detail: "Loading content state", showsProgress: true)
            case .error:
                statePanel(icon: "exclamationmark.triangle", title: "Couldn’t load this page", detail: "Retry remains available", isError: true)
            default:
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: isClassic ? 32 : 42, alignment: .center)
                Text("Track")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isClassic {
                    Text("Artist")
                        .frame(width: 120, alignment: .leading)
                }
                Text("Album")
                    .frame(width: isClassic ? 150 : 190, alignment: .leading)
                Text("Time")
                    .frame(width: 52, alignment: .trailing)
            }
            .font(theme.typography.sectionHeader)
            .foregroundStyle(theme.colors.secondaryText)
            .padding(.horizontal, theme.metrics.sectionHorizontalInset)
            .padding(.vertical, theme.metrics.smallPadding)
            .background(theme.colors.raisedSurface.swiftUIStyle)

            ForEach(0..<6, id: \.self) { index in
                fixtureRow(index: index)
            }
        }
    }

    private func fixtureRow(index: Int) -> some View {
        let isSelected = state == .selected && index == 1
        let isCurrent = state == .current && index == 1
        let isHovered = state == .hovered && index == 1
        let isPressed = state == .pressed && index == 1
        let title = state == .longText && index == 1
            ? "A long track title that must truncate before the time column"
            : "Example track \(index + 1)"
        let artist = state == .longText && index == 1
            ? "An exceptionally long artist name"
            : "Artist Name"
        let album = state == .longText && index == 1
            ? "An album name with enough content to test clipping"
            : "Album Name"

        return HStack(spacing: 0) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform")
                        .foregroundStyle(theme.colors.accent)
                } else if isHovered || isPressed {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                } else {
                    Text("\(index + 1)")
                        .font(theme.typography.trackIndex)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(width: isClassic ? 32 : 42, alignment: .center)

            if isClassic {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(artist)
                    .frame(width: 120, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)
                    Text(artist)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(album)
                .frame(width: isClassic ? 150 : 190, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(theme.colors.secondaryText)
            Text("3:42")
                .font(theme.typography.duration)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 52, alignment: .trailing)
        }
        .font(theme.typography.metadata)
        .foregroundStyle(isCurrent ? theme.colors.accent : theme.colors.primaryText)
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.trackRowVerticalPadding)
        .background(
            isSelected
                ? theme.colors.rowSelected.swiftUIStyle
                : (isCurrent ? theme.colors.rowCurrent.swiftUIStyle : (isHovered ? theme.colors.rowHover.swiftUIStyle : AnyShapeStyle(Color.clear)))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(theme.colors.focusRing)
                    .frame(width: 2)
            }
        }
        .opacity(state == .disabled ? 0.48 : 1)
    }

    private func statePanel(
        icon: String,
        title: String,
        detail: String,
        showsProgress: Bool = false,
        isError: Bool = false
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isError ? theme.colors.error : theme.colors.secondaryText)
            Text(title)
                .font(theme.typography.messageTitle)
                .foregroundStyle(theme.colors.primaryText)
            Text(detail)
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.secondaryText)
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.accent)
            }
            if isError {
                Text("Retry")
                    .font(theme.typography.button)
                    .foregroundStyle(theme.colors.inverseText)
                    .padding(.horizontal, theme.metrics.controlHorizontalPadding - 4)
                    .padding(.vertical, theme.metrics.controlVerticalPadding - 2)
                    .background(theme.colors.accent)
                    .cornerRadius(theme.metrics.smallPillCornerRadius)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.metrics.pageHorizontalInset)
        .background(isError ? theme.colors.errorContainer.swiftUIStyle : AnyShapeStyle(Color.clear))
        .overlay {
            if isError {
                Rectangle()
                    .strokeBorder(theme.colors.errorBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var player: some View {
        if isClassic {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ChromeButton(
                        title: "",
                        accessibilityLabel: "Previous track",
                        symbolName: "backward.fill",
                        style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24))
                    )
                    .disabled(state == .disabled)
                    ChromeButton(
                        title: "",
                        accessibilityLabel: state == .pressed ? "Pause" : "Play",
                        symbolName: state == .pressed ? "pause.fill" : "play.fill",
                        style: ChromeStyle(role: .transport, size: CGSize(width: 28, height: 28))
                    )
                    .disabled(state == .disabled)
                    ChromeButton(
                        title: "",
                        accessibilityLabel: "Next track",
                        symbolName: "forward.fill",
                        style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24))
                    )
                    .disabled(state == .disabled)
                    Spacer(minLength: 6)
                    Capsule()
                        .fill(theme.colors.sliderTrack)
                        .frame(width: 68, height: 4)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(width: theme.metrics.sidebarWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(width: 1)
                }

                HStack(spacing: 8) {
                    Text("1:42")
                        .font(theme.typography.mono)
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 34, alignment: .trailing)
                    ChromeSliderTrack(
                        style: ChromeSliderStyle(
                            size: CGSize(width: 180, height: 10),
                            fraction: state == .current ? 0.58 : 0.42,
                            isEnabled: state != .disabled
                        ),
                        fillsAvailableWidth: true
                    )
                    Text("3:57")
                        .font(theme.typography.mono)
                        .foregroundStyle(theme.colors.primaryText)
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
        } else {
            HStack(spacing: 10) {
                Button("◀") {}
                Button(state == .pressed ? "❚❚" : "▶") {}
                Button("▶") {}
                Rectangle()
                    .fill(theme.colors.divider)
                    .frame(width: 1, height: 28)
                Text("1:42")
                    .font(theme.typography.mono)
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.colors.sliderTrack)
                    .frame(maxWidth: .infinity, maxHeight: 4)
                Text("3:57")
                    .font(theme.typography.mono)
                Button("Queue") {}
                    .foregroundStyle(theme.colors.primaryText)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.primaryText)
            .disabled(state == .disabled)
            .padding(.horizontal, 12)
            .frame(height: theme.metrics.playerBarHeight)
            .background(theme.colors.playerBackground.swiftUIStyle)
        }
    }
}

struct ThemeVisualStateMatrix: View {
    let themeID: AppThemeID

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ThemeFixtureState.allCases) { state in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ThemeVisualFixture(
                            themeID: themeID,
                            state: state,
                            canvasSize: CGSize(width: 420, height: 300)
                        )
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 900, height: 780)
        .environment(\.appTheme, AppTheme.resolve(themeID))
    }
}

#Preview("Classic 1x long text") {
    ThemeVisualFixture(
        themeID: .classic2010,
        state: .longText,
        canvasSize: CGSize(width: 900, height: 600)
    )
    .environment(\.appTheme, .classic2010)
    .environment(\.displayScale, 1)
}

#Preview("Classic 2x long text") {
    ThemeVisualFixture(
        themeID: .classic2010,
        state: .longText,
        canvasSize: CGSize(width: 900, height: 600)
    )
    .environment(\.appTheme, .classic2010)
    .environment(\.displayScale, 2)
}

#Preview("Nanyin Dark 1x long text") {
    ThemeVisualFixture(
        themeID: .nanyinDark,
        state: .longText,
        canvasSize: CGSize(width: 900, height: 600)
    )
    .environment(\.appTheme, .nanyinDark)
    .environment(\.displayScale, 1)
}

#Preview("Classic state matrix") {
    ThemeVisualStateMatrix(themeID: .classic2010)
}

#Preview("Nanyin Dark state matrix") {
    ThemeVisualStateMatrix(themeID: .nanyinDark)
}
