//
//  AudioRenderer.swift
//  Nanyin
//
//  Bridges librespot's push model (Rust Sink::write → C callback) to
//  AVAudioEngine's pull model (AVAudioSourceNode render callback),
//  using a lock-protected ring buffer with semaphore backpressure.
//

import AVFoundation

/// Audio format fixed by the Rust side.
private let sampleRate: Double = 44_100
private let channelCount: AVAudioChannelCount = 2
/// Ring capacity: ~2 seconds of interleaved stereo f32.
private let ringCapacity = 176_400
/// Writer waits in chunks of this many samples; reader signals after
/// consuming at least this many.
private let chunkSize = 4_096

final nonisolated class AudioRenderer: @unchecked Sendable {
    static let shared = AudioRenderer()

    // MARK: - Ring buffer

    private let ring = UnsafeMutablePointer<Float>.allocate(capacity: ringCapacity)
    private var writeIndex = 0
    private var readIndex = 0
    private var filled = 0 // samples currently in the ring
    private var consumedSinceSignal = 0
    private var acceptedSamples: UInt64 = 0
    private var renderCallbacks: UInt64 = 0
    private var renderedSamples: UInt64 = 0
    private let lock = NSLock()
    /// Signalled by the reader when space frees up; the writer waits on it.
    private let spaceAvailable = DispatchSemaphore(value: 0)

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let renderQueue = DispatchQueue(label: "com.nanyin.audio.render", qos: .userInteractive)
    private let engineLock = NSLock()
    private var running = false
    private var activeGeneration: UInt64?

    /// Restart the engine when the default output device changes
    /// (headphones plugged/unplugged, bluetooth switch) — AVAudioEngine does
    /// not re-route on its own.
    private var deviceObserver: Any?

    private init() {
        // Leak the buffer intentionally (lives for the process lifetime).
        deviceObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVAudioEngineConfigurationChangeNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.restartAfterRouteChange()
        }
    }

    private func restartAfterRouteChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSLog("[nanyin] audio route changed — restarting engine")
            let wasRunning: Bool = self.lock.withLock { self.running }
            guard wasRunning else { return }
            self.restartForRecovery()
        }
    }

    // MARK: - Public API

    /// Starts the audio engine (idempotent).
    func start(generation: UInt64) {
        engineLock.lock()
        defer { engineLock.unlock() }
        let transition = lock.withLock { () -> (shouldStart: Bool, replaced: Bool) in
            if let activeGeneration, generation < activeGeneration {
                return (false, false)
            }
            let replaced = activeGeneration != generation
            activeGeneration = generation
            if running {
                if replaced {
                    resetBuffer()
                }
                return (false, replaced)
            }
            running = true
            resetBuffer()
            return (true, replaced)
        }
        if transition.replaced {
            spaceAvailable.signal()
        }
        guard transition.shouldStart else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.render(into: ablPointer, frameCount: Int(frameCount))
            return noErr
        }
        sourceNode = node

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()

        do {
            try engine.start()
        } catch {
            NSLog("AudioRenderer: engine start failed: \(error)")
            engine.detach(node)
            sourceNode = nil
            lock.withLock {
                running = false
            }
        }
    }

    /// Stops the engine and flushes the ring (track end / app quit).
    func stop() {
        stop(generation: nil)
    }

    func stop(generation: UInt64) {
        stop(generation: Optional(generation))
    }

    private func stop(generation: UInt64?) {
        engineLock.lock()
        defer { engineLock.unlock() }
        let shouldStop = lock.withLock {
            guard running,
                  generation == nil || generation == activeGeneration else { return false }
            running = false
            resetBuffer()
            return true
        }
        guard shouldStop else { return }

        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        // Wake a possibly-blocked writer so it can observe the stopped state.
        spaceAvailable.signal()
    }

    /// Flushes buffered samples but keeps the engine running (seek / skip).
    func clear(generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == activeGeneration else { return }
        resetBuffer()
        // Wake a possibly-blocked writer; it will see space and continue or
        // exit when the ring stays empty.
        spaceAvailable.signal()
    }

    /// Rebuilds only the CoreAudio output path; Spotify session, Spirc, and
    /// the decoder remain untouched.
    func restartForRecovery() {
        guard let generation = lock.withLock({ activeGeneration }) else { return }
        stop(generation: generation)
        start(generation: generation)
    }

    var playbackProgress: RendererPlaybackProgress {
        lock.withLock {
            RendererPlaybackProgress(
                acceptedSamples: acceptedSamples,
                renderCallbacks: renderCallbacks,
                renderedSamples: renderedSamples
            )
        }
    }

    // MARK: - Writer (called from the Rust audio thread)

    /// Writes interleaved stereo f32 samples. Blocks (backpressure) while the
    /// ring is full, pacing librespot's decoder to real time.
    func write(samples: UnsafePointer<Float>, count: Int, generation: UInt64) {
        var offset = 0
        while offset < count {
            lock.lock()
            if !running || generation != activeGeneration {
                // Engine stopped mid-write (track switch / quit) — drop the
                // rest instead of blocking forever on a full ring.
                lock.unlock()
                return
            }
            let free = ringCapacity - filled
            if free == 0 {
                lock.unlock()
                spaceAvailable.wait()
                continue
            }
            let toCopy = min(free, count - offset, chunkSize)
            let chunk = UnsafeBufferPointer(start: samples + offset, count: toCopy)
            for value in chunk {
                ring[writeIndex] = value
                writeIndex = (writeIndex + 1) % ringCapacity
            }
            filled += toCopy
            acceptedSamples &+= UInt64(toCopy)
            offset += toCopy
            lock.unlock()
        }
    }

    private func resetBuffer() {
        writeIndex = 0
        readIndex = 0
        filled = 0
        consumedSinceSignal = 0
    }

    // MARK: - Reader (render callback, real-time audio thread)

    private func render(into buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        lock.lock()
        renderCallbacks &+= 1
        let available = filled
        let frames = min(frameCount, available / Int(channelCount))

        if frames > 0, buffers.count >= 2,
           let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
        {
            for frame in 0 ..< frames {
                left[frame] = ring[readIndex]
                right[frame] = ring[(readIndex + 1) % ringCapacity]
                readIndex = (readIndex + 2) % ringCapacity
            }
            filled -= frames * Int(channelCount)
            consumedSinceSignal += frames * Int(channelCount)
            renderedSamples &+= UInt64(frames * Int(channelCount))

            // Wake the writer once enough space has been consumed.
            while consumedSinceSignal >= chunkSize {
                spaceAvailable.signal()
                consumedSinceSignal -= chunkSize
            }
        }
        lock.unlock()

        // Fill any remaining frames with silence (underrun).
        let rendered = frames
        if rendered < frameCount, buffers.count >= 2,
           let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
        {
            for frame in rendered ..< frameCount {
                left[frame] = 0
                right[frame] = 0
            }
        }
    }
}
