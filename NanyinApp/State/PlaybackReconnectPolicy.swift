enum PlaybackReconnectPolicy {
    static func shouldDeferRebuild(
        isPlaying: Bool,
        isBuffering: Bool,
        hasPendingPlay: Bool
    ) -> Bool {
        isPlaying && !isBuffering && !hasPendingPlay
    }
}
