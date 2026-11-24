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

        var label: String {
            switch self {
            case .low: "Low (96 kbps)"
            case .normal: "Normal (160 kbps)"
            case .high: "High (320 kbps)"
            }
        }

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

    /// Fired when bitrate, volume normalization, or device name changes so an
    /// active playback session reconnects with the new settings.
    var onPlaybackConfigChanged: () -> Void = {}

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
        sanitized(deviceNameDraft) != appliedDeviceName
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
        let clean = sanitized(deviceNameDraft)
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

    func discardPendingDeviceName() {
        deviceNameDraft = appliedDeviceName
    }

    func refreshCacheSize() {
        guard !isComputingCacheSize else { return }
        isComputingCacheSize = true
        let dir = Self.audioCacheDirectory
        Task {
            let bytes = await Task.detached(priority: .utility) {
                Self.directorySize(at: dir)
            }.value
            cacheSizeBytes = bytes
            isComputingCacheSize = false
        }
    }

    func clearCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        cacheStatusMessage = nil
        let dir = Self.audioCacheDirectory
        URLCache.shared.removeAllCachedResponses()
        Task {
            let removedError: String? = await Task.detached(priority: .utility) {
                Self.removeContents(of: dir)
            }.value
            let bytes = await Task.detached(priority: .utility) {
                Self.directorySize(at: dir)
            }.value
            cacheSizeBytes = bytes
            isClearingCache = false
            cacheStatusMessage = removedError ?? "Audio and cover art cache cleared."
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

    private func sanitized(_ raw: String) -> String {
        Self.sanitize(raw)
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
        do {
            let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for entry in entries {
                try FileManager.default.removeItem(at: entry)
            }
            return nil
        } catch {
            return "Could not clear all cached files: \(error.localizedDescription)"
        }
    }
}
