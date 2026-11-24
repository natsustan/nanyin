import AppKit
import Foundation
import Observation

/// User-configurable playback, cache, and diagnostics settings shown in the
/// Settings window (`⌘,`).
@MainActor
@Observable
final class PlaybackSettings {
    enum AudioQuality: Int, CaseIterable, Identifiable {
        case low = 96
        case normal = 160
        case high = 320

        var id: Int { rawValue }
        var shortLabel: String { "\(rawValue) kbps" }
    }

    var audioQuality: AudioQuality {
        didSet {
            guard audioQuality != oldValue else { return }
            UserDefaults.standard.set(audioQuality.rawValue, forKey: Self.qualityKey)
            onPlaybackConfigChanged()
        }
    }

    var normalizeVolume: Bool {
        didSet {
            guard normalizeVolume != oldValue else { return }
            UserDefaults.standard.set(normalizeVolume, forKey: Self.normalizeKey)
            onPlaybackConfigChanged()
        }
    }

    /// Draft Connect device name edited in Settings; applied explicitly via
    /// `applyDeviceName()` so typing doesn't reconnect on every keystroke.
    var deviceNameDraft: String
    private(set) var appliedDeviceName: String

    private(set) var cacheSizeBytes: Int64?
    private(set) var isComputingCacheSize = false
    private(set) var isClearingCache = false
    private(set) var cacheStatusMessage: String?
    private(set) var cacheStatusIsError = false

    /// Fired when bitrate, volume normalization, or device name changes so an
    /// active playback session reconnects with the new settings.
    var onPlaybackConfigChanged: () -> Void = {}
    /// Fired when the user clears caches so auxiliary caches (e.g. lyrics) clear too.
    var onCacheCleared: () -> Void = {}

    @ObservationIgnored private var cacheTask: Task<Void, Never>?
    private static let qualityKey = "PlaybackAudioBitrate"
    private static let normalizeKey = "PlaybackNormalizeVolume"
    private static let deviceNameKey = "ConnectDeviceName"

    static var defaultDeviceName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nanyin"
    }

    static var audioCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Nanyin")
            .appending(path: "audio")
    }

    var effectiveDeviceName: String {
        appliedDeviceName.isEmpty ? Self.defaultDeviceName : appliedDeviceName
    }

    var hasPendingDeviceNameChange: Bool {
        Self.sanitize(deviceNameDraft) != appliedDeviceName
    }

    init() {
        let savedQuality = UserDefaults.standard.object(forKey: Self.qualityKey) as? Int
        audioQuality = savedQuality.flatMap(AudioQuality.init(rawValue:)) ?? .high
        normalizeVolume = UserDefaults.standard.bool(forKey: Self.normalizeKey)
        let savedName = UserDefaults.standard.string(forKey: Self.deviceNameKey) ?? ""
        let clean = Self.sanitize(savedName)
        appliedDeviceName = clean
        deviceNameDraft = clean
    }

    func applyDeviceName() {
        let clean = Self.sanitize(deviceNameDraft)
        deviceNameDraft = clean
        guard clean != appliedDeviceName else { return }
        appliedDeviceName = clean
        if clean.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.deviceNameKey)
        } else {
            UserDefaults.standard.set(clean, forKey: Self.deviceNameKey)
        }
        onPlaybackConfigChanged()
    }

    func discardTransientState() {
        deviceNameDraft = appliedDeviceName
        cacheStatusMessage = nil
        cacheStatusIsError = false
    }

    func refreshCacheSize() {
        guard !isClearingCache else { return }
        cacheTask?.cancel()
        isComputingCacheSize = true
        let dir = Self.audioCacheDirectory
        cacheTask = Task {
            let bytes = await Task.detached(priority: .utility) {
                Self.directorySize(at: dir)
            }.value
            guard !Task.isCancelled else { return }
            cacheSizeBytes = bytes
            isComputingCacheSize = false
        }
    }

    func clearCache() {
        guard !isClearingCache else { return }
        cacheTask?.cancel()
        isComputingCacheSize = false
        isClearingCache = true
        cacheStatusMessage = nil
        cacheStatusIsError = false
        let dir = Self.audioCacheDirectory
        URLCache.shared.removeAllCachedResponses()
        ImageLoader.shared.clearMemoryCache()
        onCacheCleared()
        cacheTask = Task {
            let result = await Task.detached(priority: .utility) {
                let error = Self.removeContents(of: dir)
                let bytes = Self.directorySize(at: dir)
                return (error, bytes)
            }.value
            guard !Task.isCancelled else { return }
            cacheSizeBytes = result.1
            isClearingCache = false
            cacheStatusIsError = result.0 != nil
            cacheStatusMessage = result.0 ?? "Audio and cover art cache cleared."
        }
    }

    func revealLogs() {
        let logURL = PlaybackEngine.logURL
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            let dir = logURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }

    var formattedCacheSize: String {
        guard let cacheSizeBytes else {
            return isComputingCacheSize ? "Calculating…" : "—"
        }
        return ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    private static func sanitize(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    }

    private nonisolated static func directorySize(at url: URL?) -> Int64 {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private nonisolated static func removeContents(of url: URL?) -> String? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            return "Could not read cache directory: \(error.localizedDescription)"
        }
        var failed = 0
        for entry in entries {
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                failed += 1
            }
        }
        return failed == 0
            ? nil
            : "Cleared cache, but \(failed) file\(failed == 1 ? "" : "s") in use could not be removed."
    }
}
