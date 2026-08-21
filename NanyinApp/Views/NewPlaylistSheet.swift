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
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Playlist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("My playlist", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            if let error = app.playlistCreationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if app.isCreatingPlaylist {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    app.cancelNewPlaylistSheet()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(app.isCreatingPlaylist)
                Button("Create") {
                    app.createPlaylist(named: name)
                }
                .keyboardShortcut(.defaultAction) // Return submits
                .disabled(trimmedName.isEmpty || app.isCreatingPlaylist)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.background)
        .interactiveDismissDisabled(app.isCreatingPlaylist)
        .onAppear { nameFocused = true }
    }
}
