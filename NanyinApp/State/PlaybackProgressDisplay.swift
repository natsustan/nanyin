struct PlaybackProgressDisplay {
    private(set) var positionMs: UInt32 = 0
    private(set) var draggingFraction: Double?

    func effectivePositionMs(durationMs: UInt32) -> UInt32 {
        guard let draggingFraction else { return positionMs }
        return UInt32(draggingFraction * Double(max(durationMs, 1)))
    }

    mutating func update(positionMs: UInt32) {
        guard draggingFraction == nil, positionMs != self.positionMs else { return }
        self.positionMs = positionMs
    }

    mutating func drag(to fraction: Double) {
        draggingFraction = fraction
    }

    mutating func commitSeek(to fraction: Double, durationMs: UInt32) {
        positionMs = UInt32(fraction * Double(max(durationMs, 1)))
        draggingFraction = nil
    }

    mutating func cancelDrag() {
        draggingFraction = nil
    }
}
