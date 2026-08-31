enum PlaybackReconnectPolicy {
    static func shouldDeferRebuild(
        isPlaying: Bool,
        isBuffering: Bool,
        hasPendingPlay: Bool
    ) -> Bool {
        isPlaying && !isBuffering && !hasPendingPlay
    }

    static func shouldWaitForActivation(
        isAppActive: Bool,
        isPlaying: Bool,
        isBuffering: Bool,
        hasPendingPlay: Bool
    ) -> Bool {
        !isAppActive && !isPlaying && !isBuffering && !hasPendingPlay
    }
}
