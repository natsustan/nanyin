//
//  FollowedArtistsView.swift
//  Nanyin
//

import SwiftUI

/// Cursor-paginated artist library with a client-side name filter. The page
/// owns one vertical scroll region and keeps hover state card-local.
struct FollowedArtistsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    @State private var filterText = ""

    private var trimmedFilter: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleArtists: [SpotifyClient.Artist] {
        var artists = app.followedArtists
        if !trimmedFilter.isEmpty {
            artists = artists.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedFilter)
            }
        }
        artists.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedAscending || (order == .orderedSame && $0.id < $1.id)
        }
        return artists
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.colors.divider)
            if app.followedArtistsError != nil, app.hasFollowedArtistsData {
                refreshErrorBanner
            }
            content
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Followed Artists")
                    .font(theme.typography.collectionHeader)
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
                Text(countLabel)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            HStack(spacing: 12) {
                filterField
                Spacer()
            }
        }
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset)
        .padding(.bottom, theme.metrics.headerBottomInset)
    }

    private var countLabel: String {
        app.followedArtistCount == 1 ? "1 artist" : "\(app.followedArtistCount) artists"
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.secondaryText)
            TextField("Filter artists…", text: $filterText)
                .textFieldStyle(.plain)
                .font(theme.typography.metadata)
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.metrics.compactFieldHorizontalPadding)
        .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
        .background(theme.colors.inputBackground.swiftUIStyle)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadius))
        .frame(width: 220)
        .disabled(!app.hasCompleteFollowedArtistsData)
        .opacity(app.hasCompleteFollowedArtistsData ? 1 : 0.55)
        .help(app.hasCompleteFollowedArtistsData ? "Filter artists" : "Retry to load all artists before filtering")
    }

    @ViewBuilder
    private var content: some View {
        if let error = app.followedArtistsError, !app.hasFollowedArtistsData {
            errorState(error)
        } else if !app.hasFollowedArtistsData {
            VStack(spacing: 12) {
                ProgressView().tint(theme.colors.accent)
                Text("Loading followed artists…")
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if app.followedArtists.isEmpty {
            emptyState
        } else if visibleArtists.isEmpty {
            VStack(spacing: 10) {
                Text("No artists match “\(trimmedFilter)”")
                    .font(theme.typography.bodyEmphasis)
                    .foregroundStyle(theme.colors.secondaryText)
                Button("Clear filter") { filterText = "" }
                    .buttonStyle(.link)
                    .tint(theme.colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            artistGrid
        }
    }

    private var artistGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: theme.metrics.collectionGridMinimum),
                    spacing: theme.metrics.smallPadding + 8
                )],
                spacing: theme.metrics.smallPadding + 8
            ) {
                ForEach(visibleArtists) { artist in
                    FollowedArtistCard(artist: artist)
                }
            }
            .padding(.horizontal, theme.metrics.pageHorizontalInset)
            .padding(.top, theme.metrics.sectionTopPadding + 4)
            .padding(.bottom, theme.metrics.pageBottomInset + 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
            Text("No followed artists yet")
                .font(theme.typography.collectionTitle)
                .foregroundStyle(theme.colors.primaryText)
            Text("Follow artists from their pages to keep them here.")
                .font(theme.typography.metadata)
                .foregroundStyle(theme.colors.secondaryText)
            Button {
                app.focusSearch()
            } label: {
                Text("Find artists")
                    .font(theme.typography.button)
                    .foregroundStyle(theme.colors.inverseText)
                    .padding(.horizontal, theme.metrics.controlHorizontalPadding - 4)
                    .padding(.vertical, theme.metrics.controlVerticalPadding - 2)
                    .background(theme.colors.accent)
                    .cornerRadius(theme.metrics.compactPillCornerRadius)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(theme.colors.warning)
            Text(message)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
            Button("Retry") { app.refreshFollowedArtists(force: true) }
                .buttonStyle(.link)
                .tint(theme.colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshErrorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.warning)
            Text(refreshErrorMessage)
                .font(theme.typography.bannerText)
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
            Button("Retry") { app.refreshFollowedArtists(force: true) }
                .buttonStyle(.link)
                .tint(theme.colors.accent)
        }
        .padding(.horizontal, theme.metrics.cardPadding)
        .padding(.vertical, theme.metrics.fieldVerticalPadding)
        .background(theme.colors.warningContainer.swiftUIStyle)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius)
                .strokeBorder(theme.colors.warningBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius))
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.sectionTopPadding)
    }

    private var refreshErrorMessage: String {
        if !app.hasCompleteFollowedArtistsData {
            return "Showing \(app.followedArtists.count) of \(app.followedArtistCount) artists."
        }
        return "Couldn’t refresh all followed artists."
    }
}

private struct FollowedArtistCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let artist: SpotifyClient.Artist
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            portrait

            Text(artist.name)
                .font(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 18,
                    maxHeight: 18,
                    alignment: .top
                )
        }
        .padding(theme.metrics.smallPadding)
        .background(hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear))
        .cornerRadius(theme.metrics.cardCornerRadius)
        .contentShape(Rectangle())
        .onTapGesture {
            app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
        }
        .contextMenu {
            Button {
                app.playArtist(id: artist.id)
            } label: {
                Label("Play Artist", systemImage: "play")
            }
            Divider()
            Button {
                if app.isArtistFollowed(artist.id) {
                    app.unfollowArtist(artist)
                } else {
                    app.followArtist(artist)
                }
            } label: {
                Label(
                    app.isArtistFollowed(artist.id) ? "Unfollow Artist" : "Follow Artist",
                    systemImage: app.isArtistFollowed(artist.id)
                        ? "person.badge.minus"
                        : "person.badge.plus"
                )
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "https://open.spotify.com/artist/\(artist.id)",
                    forType: .string
                )
            } label: {
                Label("Copy Artist Link", systemImage: "link")
            }
        }
        .onHover { hovering = $0 }
        .linkCursor()
    }

    private var portrait: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ArtworkView(url: artist.artworkURL, size: theme.metrics.collectionArtworkSize) {
                    ZStack {
                        Rectangle().fill(theme.colors.placeholderBackground.swiftUIStyle)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .clipShape(theme.id == .classic2010 ? AnyShape(Rectangle()) : AnyShape(Circle()))
            .shadow(
                color: theme.colors.shadow.opacity(0.35),
                radius: theme.metrics.shadowRadius,
                y: theme.metrics.shadowYOffset
            )
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    Button {
                        app.playArtist(id: artist.id)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.colors.inverseText)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(theme.colors.accent))
                            .shadow(color: theme.colors.shadow.opacity(0.4), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Play Artist")
                    .padding(theme.metrics.smallPadding)
                }
            }
    }
}
