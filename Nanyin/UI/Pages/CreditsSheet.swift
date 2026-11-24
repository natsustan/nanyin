import SwiftUI

/// A song's credits as the desktop client lists them: performers, writers,
/// producers, each name opening its artist's page.
struct CreditsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let credits: TrackCredits

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: credits.title, subtitle: credits.artists)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.content)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(TexturedButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Theme.graphite)
            .hairline(.top, Theme.graphiteEdge)
        }
        .frame(width: 380, height: 440)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if let found = credits.credits {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(found.roles.enumerated()), id: \.offset) { _, role in
                        if !role.artists.isEmpty {
                            GraphiteHeader { Text(role.title) }
                            ForEach(Array(role.artists.enumerated()), id: \.offset) { index, credit in
                                CreditRow(credit: credit, index: index, open: open)
                            }
                        }
                    }
                    if !found.sources.isEmpty {
                        Text("Source: \(found.sources.joined(separator: ", "))")
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
            }
        } else {
            PlaceholderText(message: credits.error ?? "Loading…")
        }
    }

    private func open(_ route: Route) {
        dismiss()
        app.navigator.go(to: route)
    }
}

private struct CreditRow: View {
    let credit: CoreCredits.Credit
    let index: Int
    let open: (Route) -> Void
    @State private var hovered = false

    var body: some View {
        let route = Route(uri: credit.uri)
        HStack(spacing: 8) {
            Text(credit.name)
                .font(AquaFont.regular(12))
                .foregroundStyle(Theme.text)
                .underline(hovered && route != nil)
            Spacer(minLength: 0)
            Text(credit.subroles.map(\.localizedCapitalized).joined(separator: ", "))
                .font(AquaFont.regular(11))
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Color(nsColor: Theme.row(index)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .linkPointer(route != nil)
        .onTapGesture { route.map(open) }
    }
}
