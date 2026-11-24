import Foundation

/// A Spotify resource parsed from a `spotify:` URI or an `open.spotify.com` URL.
public enum SpotifyTarget: Equatable, Hashable, Sendable {
    case track(id: String)
    case album(id: String)
    case artist(id: String)
    case playlist(id: String)

    public var uri: String {
        switch self {
        case .track(let id): "spotify:track:\(id)"
        case .album(let id): "spotify:album:\(id)"
        case .artist(let id): "spotify:artist:\(id)"
        case .playlist(let id): "spotify:playlist:\(id)"
        }
    }
}

/// Parses Spotify URIs and share URLs that a listener pastes into search.
public enum SpotifyLink {
    public static func parse(_ raw: String) -> SpotifyTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("spotify:") {
            return parseURI(trimmed)
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host()?.lowercased(),
              host == "open.spotify.com" || host == "play.spotify.com"
        else { return nil }

        var segments = url.pathComponents.filter { $0 != "/" }
        // Localized Spotify URLs carry a leading `/intl-xx` segment.
        if let first = segments.first, first.lowercased().hasPrefix("intl-") {
            segments.removeFirst()
        }
        // Legacy `/user/<name>/playlist/<id>` URLs.
        if segments.count >= 4, segments[0].lowercased() == "user", segments[2].lowercased() == "playlist" {
            return makeTarget(kind: "playlist", id: segments[3])
        }
        guard segments.count >= 2 else { return nil }
        return makeTarget(kind: segments[0].lowercased(), id: segments[1])
    }

    private static func parseURI(_ uri: String) -> SpotifyTarget? {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.first?.lowercased() == "spotify" else { return nil }
        if parts.count == 3 {
            return makeTarget(kind: parts[1].lowercased(), id: parts[2])
        }
        // Legacy `spotify:user:<username>:playlist:<id>` URIs.
        if parts.count == 5, parts[1].lowercased() == "user", parts[3].lowercased() == "playlist" {
            return makeTarget(kind: "playlist", id: parts[4])
        }
        return nil
    }

    private static func makeTarget(kind: String, id: String) -> SpotifyTarget? {
        guard isValidID(id) else { return nil }
        switch kind {
        case "track": return .track(id: id)
        case "album": return .album(id: id)
        case "artist": return .artist(id: id)
        case "playlist": return .playlist(id: id)
        default: return nil
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9")
                || (scalar >= "a" && scalar <= "z")
                || (scalar >= "A" && scalar <= "Z")
        }
    }
}
