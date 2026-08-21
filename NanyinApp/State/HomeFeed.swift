//
//  HomeFeed.swift
//  Nanyin
//

import Foundation

/// Pure derivation for the personalized home page — no I/O. AppModel owns
/// fetching, epoch/generation fencing, and publication; this namespace maps
/// raw responses onto display models so the mapping stays testable without
/// the app model (same pattern as SavedAlbumCache).
enum HomeFeed {
    /// One card on the Recently Played strip: the context a recent play came
    /// from (album / playlist / artist), or the track's own album when there
    /// is no usable context (direct plays, or playlist contexts whose name is
    /// unknown — editorial mixes do not appear in /v1/me/playlists).
    struct Card: Identifiable, Hashable {
        enum Kind: Hashable {
            case album, playlist, artist
        }

        let kind: Kind
        /// Album / playlist / artist id the card navigates to.
        let refID: String
        let title: String
        let subtitle: String
        let artworkURL: URL?

        var id: String { "\(kind):\(refID)" }
    }

    /// Maps a context type string ("album" / "playlist" / "artist") to a
    /// card kind. Anything else (e.g. "show") is not card-able.
    static func contextKind(_ type: String?) -> Card.Kind? {
        switch type {
        case "album": .album
        case "playlist": .playlist
        case "artist": .artist
        default: nil
        }
    }

    /// Extracts the id from a context URI, kind-checked by prefix.
    static func contextRefID(_ uri: String?, kind: Card.Kind) -> String? {
        guard let uri else { return nil }
        let prefix: String
        switch kind {
        case .album: prefix = "spotify:album:"
        case .playlist: prefix = "spotify:playlist:"
        case .artist: prefix = "spotify:artist:"
        }
        guard uri.hasPrefix(prefix) else { return nil }
        let id = String(uri.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    /// Dedupes by card id and caps the strip. History order is
    /// most-recently-played first (server order).
    static func recentlyPlayedCards(
        from history: [SpotifyClient.PlayHistoryItem],
        playlists: [SpotifyClient.PlaylistInfo],
        limit: Int = 10
    ) -> [Card] {
        var result: [Card] = []
        var seen = Set<String>()
        for item in history {
            guard let card = card(for: item, playlists: playlists) else { continue }
            if seen.insert(card.id).inserted {
                result.append(card)
                if result.count >= limit { break }
            }
        }
        return result
    }

    /// Card for one history item. Playlist contexts resolve against the
    /// user's playlist list for a name and cover; unknown playlists fall back
    /// to the track's album so editorial mixes never render a nameless card.
    static func card(
        for item: SpotifyClient.PlayHistoryItem,
        playlists: [SpotifyClient.PlaylistInfo]
    ) -> Card? {
        let track = item.track
        switch contextKind(item.contextType) {
        case .playlist:
            if let id = contextRefID(item.contextURI, kind: .playlist),
               let info = playlists.first(where: { $0.id == id }) {
                return Card(
                    kind: .playlist,
                    refID: id,
                    title: info.name,
                    subtitle: "Playlist",
                    artworkURL: info.artworkURL
                )
            }
        case .artist:
            if let id = contextRefID(item.contextURI, kind: .artist),
               let artist = track.artists.first(where: { $0.id == id }) {
                return Card(
                    kind: .artist,
                    refID: artist.id,
                    title: artist.name,
                    subtitle: "Artist",
                    artworkURL: artist.artworkURL
                )
            }
        case .album, nil:
            break
        }
        return albumCard(for: track)
    }

    /// The track's own album as a card. Tracks without an album id (episodes,
    /// local files) produce no card.
    static func albumCard(for track: SpotifyClient.Track) -> Card? {
        guard let albumId = track.albumId, !albumId.isEmpty else { return nil }
        return Card(
            kind: .album,
            refID: albumId,
            title: track.albumName,
            subtitle: track.artists.map(\.name).joined(separator: ", "),
            artworkURL: track.artworkURL
        )
    }
}
