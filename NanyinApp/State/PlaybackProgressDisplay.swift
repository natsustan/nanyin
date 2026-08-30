struct PlaybackProgressDisplay {
    private static let seekConfirmationToleranceMs: UInt32 = 1_500
    private static let seekConfirmationTimeout: Duration = .seconds(3)

    private(set) var positionMs: UInt32 = 0
    private(set) var draggingFraction: Double?
    private var pendingSeekTargetMs: UInt32?
    private var seekConfirmationDeadline: ContinuousClock.Instant?

    init(positionMs: UInt32 = 0) {
        self.positionMs = positionMs
    }

    func effectivePositionMs(durationMs: UInt32) -> UInt32 {
        guard let draggingFraction else { return positionMs }
        return UInt32(draggingFraction * Double(max(durationMs, 1)))
    }

    mutating func update(
        positionMs: UInt32,
        confirmedPositionMs: UInt32,
        now: ContinuousClock.Instant = .now
    ) {
        guard draggingFraction == nil else { return }

        if let target = pendingSeekTargetMs,
           let deadline = seekConfirmationDeadline {
            let distance = target > confirmedPositionMs
                ? target - confirmedPositionMs
                : confirmedPositionMs - target
            if distance <= Self.seekConfirmationToleranceMs {
                pendingSeekTargetMs = nil
                seekConfirmationDeadline = nil
                self.positionMs = target
                return
            }
            guard now >= deadline else { return }
            pendingSeekTargetMs = nil
            seekConfirmationDeadline = nil
        }

        guard positionMs != self.positionMs else { return }
        self.positionMs = positionMs
    }

    mutating func drag(to fraction: Double) {
        draggingFraction = fraction
    }

    mutating func commitSeek(
        to fraction: Double,
        durationMs: UInt32,
        now: ContinuousClock.Instant = .now
    ) {
        let target = UInt32(fraction * Double(max(durationMs, 1)))
        positionMs = target
        draggingFraction = nil
        pendingSeekTargetMs = target
        seekConfirmationDeadline = now.advanced(by: Self.seekConfirmationTimeout)
    }

    mutating func cancelDrag() {
        draggingFraction = nil
    }

    mutating func resetInteraction() {
        draggingFraction = nil
        pendingSeekTargetMs = nil
        seekConfirmationDeadline = nil
    }
}
