/// Pure state machine for one id's serialized optimistic membership writes
/// (Liked Songs tracks, saved albums, followed artists). Latest local intent
/// always wins over confirmed server state.
///
/// `confirmedSaved` is the last state known to have reached Spotify.
/// `desiredSaved` is the user's latest intent. They must remain separate:
/// rolling back by merely inverting the last click is incorrect when several
/// clicks and failed requests interleave.
struct MembershipMutation: Equatable {
    struct Attempt: Equatable {
        let revision: UInt64
        let saved: Bool
    }

    enum Resolution: Equatable {
        /// The user's latest intent still differs from the confirmed server
        /// state, so the writer should send another request.
        case persistLatest
        /// UI and server state agree. A successful write should temporarily
        /// mask read-after-write lag; a failed obsolete write should not.
        case settled(maskServerLag: Bool)
        /// The latest write failed, so the UI must return to this confirmed
        /// server state.
        case rollback(to: Bool)
    }

    private(set) var confirmedSaved: Bool
    private(set) var desiredSaved: Bool
    private(set) var revision: UInt64

    init(confirmedSaved: Bool, desiredSaved: Bool) {
        self.confirmedSaved = confirmedSaved
        self.desiredSaved = desiredSaved
        revision = 1
    }

    mutating func setDesired(_ saved: Bool) {
        desiredSaved = saved
        revision &+= 1
    }

    /// Incorporates a newer server observation without changing the user's
    /// intent or invalidating the attempt currently in flight.
    mutating func observeConfirmedState(_ saved: Bool) {
        confirmedSaved = saved
    }

    func nextAttempt() -> Attempt {
        Attempt(revision: revision, saved: desiredSaved)
    }

    mutating func resolve(_ attempt: Attempt, succeeded: Bool) -> Resolution {
        if succeeded {
            confirmedSaved = attempt.saved
        }

        if desiredSaved == confirmedSaved {
            return .settled(maskServerLag: succeeded)
        }
        if revision != attempt.revision {
            return .persistLatest
        }
        return .rollback(to: confirmedSaved)
    }
}

/// A new prefix proves positions only for the rows it actually returned.
/// Keep the old tail visible while loading, but do not use its stale offsets.
enum LikedTrackPositions {
    static func mergePrefix(
        cached: [SpotifyClient.Track], prefix: [SpotifyClient.Track]
    ) -> [SpotifyClient.Track] {
        let ids = Set(prefix.map(\.id))
        return prefix + cached.filter { !ids.contains($0.id) }.map { track in
            var copy = track
            copy.contextPosition = nil
            return copy
        }
    }

    static func prefixMatches(cached: [SpotifyClient.Track], page: SpotifyClient.LikedTracksPage) -> Bool {
        // An entirely filtered prefix supplies no identity anchor.
        guard !page.tracks.isEmpty || page.rawCount == 0 else { return false }
        let cachedPrefix = Array(cached.prefix(page.tracks.count))
        return cachedPrefix.map(\.id) == page.tracks.map(\.id)
            && cachedPrefix.map(\.contextPosition) == page.tracks.map(\.contextPosition)
    }
}
