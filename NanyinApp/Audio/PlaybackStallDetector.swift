//
//  PlaybackStallDetector.swift
//  Nanyin
//

import Foundation

struct CorePlaybackProgress: Equatable {
    static let noPlayRequest = UInt64.max

    let playRequestID: UInt64
    let decoderPackets: UInt64
    let pcmWrites: UInt64
    let downloadWaiters: UInt64
    let confirmedPositionMs: UInt32
}

struct RendererPlaybackProgress: Equatable {
    let acceptedSamples: UInt64
    let renderCallbacks: UInt64
    let renderedSamples: UInt64
}

struct PlaybackPipelineSnapshot: Equatable {
    let core: CorePlaybackProgress
    let renderer: RendererPlaybackProgress
}

struct PlaybackStallDetector {
    private struct Attempt: Equatable {
        let generation: UInt64
        let playRequestID: UInt64
    }

    enum Stage: String, Equatable {
        case downloader
        case decoder
        case pcm
        case renderer
    }

    struct Recovery: Equatable {
        let stage: Stage
        let positionMs: UInt32
    }

    private let stallThresholdMs: UInt64
    private let maxObservationGapMs: UInt64
    private var attempt: Attempt?
    private var progressBaseline: PlaybackPipelineSnapshot?
    private var lastRenderedProgressMs: UInt64?
    private var lastObservationMs: UInt64?
    private var recoveredAttempt: Attempt?

    init(stallThresholdMs: UInt64 = 12_000, maxObservationGapMs: UInt64 = 5_000) {
        self.stallThresholdMs = stallThresholdMs
        self.maxObservationGapMs = maxObservationGapMs
    }

    mutating func observe(
        _ snapshot: PlaybackPipelineSnapshot,
        generation: UInt64,
        nowMs: UInt64,
        expectsPlayback: Bool
    ) -> Recovery? {
        guard expectsPlayback,
              snapshot.core.playRequestID != CorePlaybackProgress.noPlayRequest else {
            suspend()
            return nil
        }

        let currentAttempt = Attempt(
            generation: generation,
            playRequestID: snapshot.core.playRequestID
        )
        let observationWasInterrupted = lastObservationMs.map {
            nowMs >= $0 && nowMs - $0 > maxObservationGapMs
        } ?? false
        lastObservationMs = nowMs
        if attempt != currentAttempt || observationWasInterrupted {
            attempt = currentAttempt
            progressBaseline = snapshot
            lastRenderedProgressMs = nowMs
        }

        guard let baseline = progressBaseline,
              let lastRenderedProgressMs else {
            progressBaseline = snapshot
            self.lastRenderedProgressMs = nowMs
            return nil
        }

        if snapshot.renderer.renderedSamples > baseline.renderer.renderedSamples {
            progressBaseline = snapshot
            self.lastRenderedProgressMs = nowMs
            return nil
        }

        guard nowMs >= lastRenderedProgressMs,
              nowMs - lastRenderedProgressMs >= stallThresholdMs,
              recoveredAttempt != currentAttempt else {
            return nil
        }

        recoveredAttempt = currentAttempt
        return Recovery(
            stage: classify(baseline: baseline, current: snapshot),
            positionMs: snapshot.core.confirmedPositionMs
        )
    }

    mutating func suspend() {
        attempt = nil
        progressBaseline = nil
        lastRenderedProgressMs = nil
        lastObservationMs = nil
    }

    static func recoveryMadeProgress(
        from baseline: PlaybackPipelineSnapshot,
        to current: PlaybackPipelineSnapshot
    ) -> Bool {
        current.renderer.renderedSamples > baseline.renderer.renderedSamples
    }

    private func classify(
        baseline: PlaybackPipelineSnapshot,
        current: PlaybackPipelineSnapshot
    ) -> Stage {
        guard current.renderer.renderCallbacks > baseline.renderer.renderCallbacks else {
            return .renderer
        }
        guard current.core.decoderPackets > baseline.core.decoderPackets else {
            return current.core.downloadWaiters > 0 ? .downloader : .decoder
        }
        guard current.core.pcmWrites > baseline.core.pcmWrites,
              current.renderer.acceptedSamples > baseline.renderer.acceptedSamples else {
            return .pcm
        }
        return .renderer
    }
}
