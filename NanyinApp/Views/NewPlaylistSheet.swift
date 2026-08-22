//
//  NewPlaylistSheet.swift
//  Nanyin
//

import SwiftUI

/// New Playlist sheet (M4.5). Name is the only MVP field; the playlist is
/// created private by default. While Create is in flight, duplicate
/// submission and dismissal are both disabled. Failures show a retryable
/// inline error and keep the entered name; Cancel makes no request.
struct NewPlaylistSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetTitle

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(theme.typography.fieldLabel)
                    .foregroundStyle(theme.colors.secondaryText)
                nameField
            }

            if let error = app.playlistCreationError {
                Text(error)
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if app.isCreatingPlaylist {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if theme.id == .classic2010 {
                    classicActions
                } else {
                    darkActions
                }
            }
        }
        .padding(theme.metrics.sheetPadding)
        .frame(width: theme.metrics.sheetWidth)
        .background(theme.colors.contentBackground.swiftUIStyle)
        .interactiveDismissDisabled(app.isCreatingPlaylist)
        .onAppear { nameFocused = true }
    }

    private var sheetTitle: some View {
        Text("New Playlist")
            .font(theme.typography.sheetTitle)
            .foregroundStyle(theme.colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, theme.id == .classic2010 ? theme.metrics.smallPadding : 0)
            .overlay(alignment: .bottom) {
                if theme.id == .classic2010 {
                    Rectangle()
                        .fill(theme.colors.divider)
                        .frame(height: 1)
                }
            }
    }

    @ViewBuilder
    private var nameField: some View {
        if theme.id == .classic2010 {
            TextField("My playlist", text: $name)
                .textFieldStyle(.plain)
                .font(theme.typography.body)
                .padding(.horizontal, theme.metrics.compactFieldHorizontalPadding)
                .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
                .background(theme.colors.inputBackground.swiftUIStyle)
                .overlay {
                    Rectangle()
                        .strokeBorder(nameFocused ? theme.colors.focusRing : theme.colors.border, lineWidth: 1)
                }
                .focused($nameFocused)
        } else {
            TextField("My playlist", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
        }
    }

    private var darkActions: some View {
        Group {
            Button("Cancel") {
                app.cancelNewPlaylistSheet()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(app.isCreatingPlaylist)
            Button("Create") {
                app.createPlaylist(named: name)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty || app.isCreatingPlaylist)
        }
    }

    private var classicActions: some View {
        Group {
            Button("Cancel") {
                app.cancelNewPlaylistSheet()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(app.isCreatingPlaylist)
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.primaryText)
            .padding(.horizontal, theme.metrics.controlHorizontalPadding - 4)
            .padding(.vertical, theme.metrics.controlVerticalPadding - 2)
            .background(theme.colors.raisedSurface.swiftUIStyle)
            .overlay {
                Rectangle().strokeBorder(theme.colors.border, lineWidth: 1)
            }

            Button("Create") {
                app.createPlaylist(named: name)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty || app.isCreatingPlaylist)
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.inverseText)
            .padding(.horizontal, theme.metrics.controlHorizontalPadding - 4)
            .padding(.vertical, theme.metrics.controlVerticalPadding - 2)
            .background(theme.colors.accent)
            .overlay {
                Rectangle().strokeBorder(theme.colors.focusRing, lineWidth: 1)
            }
            .opacity(trimmedName.isEmpty || app.isCreatingPlaylist ? 0.5 : 1)
        }
    }
}
