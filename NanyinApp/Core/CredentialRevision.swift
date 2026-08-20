/// Generation fence for refresh-token persistence.
///
/// A refresh captures `snapshot` before its network request. Sign-out calls
/// `invalidate()` before deleting the credential, so a late response carrying
/// a replacement refresh token can no longer persist against that snapshot.
struct CredentialRevision: Equatable {
    private(set) var value: UInt64 = 0

    var snapshot: UInt64 { value }

    mutating func invalidate() {
        value &+= 1
    }

    func accepts(_ snapshot: UInt64) -> Bool {
        value == snapshot
    }
}

/// Pure lifecycle state used by the token coordinator around async refreshes.
struct CredentialPersistenceState: Equatable {
    private var revision = CredentialRevision()
    private(set) var isClearing = false

    func beginRefresh() -> UInt64? {
        isClearing ? nil : revision.snapshot
    }

    mutating func beginNewSession() -> UInt64 {
        installNewSession()
        return revision.snapshot
    }

    mutating func beginClear() {
        revision.invalidate()
        isClearing = true
    }

    mutating func installNewSession() {
        revision.invalidate()
        isClearing = false
    }

    func acceptsRefresh(_ snapshot: UInt64) -> Bool {
        !isClearing && revision.accepts(snapshot)
    }
}
