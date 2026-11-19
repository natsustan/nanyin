import NanyinKit
import SwiftUI

/// The start page: what was played lately on this account.
struct WhatsNewPage: View {
    @Environment(AppModel.self) private var app
    @State private var list: TrackList?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "What's New", subtitle: error ?? "Recently played")
            if let list {
                TrackListTable(list: list, columns: [.indicator, .track, .artist, .time, .album])
            } else {
                Theme.content
            }
        }
        .task {
            guard list == nil else { return }
            do {
                var seen = Set<String>()
                let tracks = try await app.account.api.recentlyPlayed().map(\.track).filter { seen.insert($0.uri).inserted }
                list = .tracks(tracks)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
