import Foundation
import NanyinKit
import Observation

/// On-demand Spotify Connect device picker model. Never polls in the background:
/// devices are fetched only when the listener opens the picker or clicks Refresh.
@MainActor
@Observable
final class ConnectDevices {
    private(set) var devices: [ConnectDevice] = []
    private(set) var isLoading = false
    private(set) var isTransferring = false
    private(set) var error: String?
    /// Older Web API tokens created before playback scopes were added get 403
    /// on `/me/player/devices`. Taking over onto this Mac still works via librespot.
    private(set) var needsResignInForDevices = false

    private let api: SpotifyWebAPI
    private let session: PlaybackSession
    private let player: Player
    private let notices: Notices
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(api: SpotifyWebAPI, session: PlaybackSession, player: Player, notices: Notices) {
        self.api = api
        self.session = session
        self.player = player
        self.notices = notices
    }

    /// Other Spotify Connect devices (excluding Nanyin's own local Connect device).
    var remoteDevices: [ConnectDevice] {
        let localID = session.localDeviceID
        return devices.filter { $0.id != localID }
    }

    var localIsActive: Bool {
        if let local = devices.first(where: { $0.id == session.localDeviceID }) {
            return local.is_active
        }
        return session.isReady && !player.playingElsewhere && player.track != nil
    }

    func refresh() {
        loadTask?.cancel()
        isLoading = true
        error = nil
        needsResignInForDevices = false
        let currentGen = generation
        loadTask = Task {
            do {
                let found = try await api.devices()
                guard !Task.isCancelled, generation == currentGen else { return }
                devices = found
                isLoading = false
            } catch is CancellationError {
            } catch WebAPIError.http(403, _) {
                guard generation == currentGen else { return }
                devices = []
                needsResignInForDevices = true
                isLoading = false
            } catch {
                guard generation == currentGen else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func transferToThisMac() {
        player.transferToThisMac()
        scheduleDelayedRefresh()
    }

    func transfer(to device: ConnectDevice) {
        guard !device.is_restricted, let id = device.id, !isTransferring else { return }
        if id == session.localDeviceID {
            transferToThisMac()
            return
        }
        isTransferring = true
        error = nil
        let currentGen = generation
        let shouldPlay: Bool? = player.isPlaying ? true : nil
        transferTask?.cancel()
        transferTask = Task {
            defer { if generation == currentGen { isTransferring = false } }
            do {
                try await api.transferPlayback(deviceID: id, play: shouldPlay)
                guard !Task.isCancelled, generation == currentGen else { return }
                scheduleDelayedRefresh()
            } catch is CancellationError {
            } catch WebAPIError.http(403, _) {
                guard generation == currentGen else { return }
                needsResignInForDevices = true
            } catch {
                guard generation == currentGen else { return }
                notices.report("Could not switch to “\(device.name)”: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        transferTask?.cancel()
        transferTask = nil
        devices = []
        isLoading = false
        isTransferring = false
        error = nil
        needsResignInForDevices = false
    }

    private func scheduleDelayedRefresh() {
        let currentGen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, generation == currentGen else { return }
            refresh()
        }
    }
}
