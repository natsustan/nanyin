/// Pure state machine for one track's serialized optimistic like writes.
///
/// `confirmedLiked` is the last state known to have reached Spotify.
/// `desiredLiked` is the user's latest intent. They must remain separate:
/// rolling back by merely inverting the last click is incorrect when several
/// clicks and failed requests interleave.
struct LikeMutation: Equatable {
    struct Attempt: Equatable {
        let revision: UInt64
        let liked: Bool
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

    private(set) var confirmedLiked: Bool
    private(set) var desiredLiked: Bool
    private(set) var revision: UInt64

    init(confirmedLiked: Bool, desiredLiked: Bool) {
        self.confirmedLiked = confirmedLiked
        self.desiredLiked = desiredLiked
        revision = 1
    }

    mutating func setDesired(_ liked: Bool) {
        desiredLiked = liked
        revision &+= 1
    }

    func nextAttempt() -> Attempt {
        Attempt(revision: revision, liked: desiredLiked)
    }

    mutating func resolve(_ attempt: Attempt, succeeded: Bool) -> Resolution {
        if succeeded {
            confirmedLiked = attempt.liked
        }

        if desiredLiked == confirmedLiked {
            return .settled(maskServerLag: succeeded)
        }
        if revision != attempt.revision {
            return .persistLatest
        }
        return .rollback(to: confirmedLiked)
    }
}
