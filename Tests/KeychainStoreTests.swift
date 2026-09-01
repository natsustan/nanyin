import Foundation

@main
private enum KeychainStoreTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let first = try KeychainStore.spotifyDeviceId(in: root, legacyDeviceIdProvider: { nil })
        let second = try KeychainStore.spotifyDeviceId(in: root) {
            fatalError("an existing device id file must win over legacy storage")
        }
        expect(first == second, "device id must remain stable")
        expect(isValidDeviceId(first), "device id must be 20 lowercase hex characters")

        let directory = root.appendingPathComponent("Nanyin", isDirectory: true)
        let file = directory.appendingPathComponent("spotify-device-id")
        try expect(try permissions(of: directory) == 0o700, "device id directory must be owner-only")
        try expect(try permissions(of: file) == 0o600, "device id file must be owner-only")

        try Data("invalid".utf8).write(to: file, options: .atomic)
        do {
            _ = try KeychainStore.spotifyDeviceId(in: root, legacyDeviceIdProvider: { nil })
            fatalError("a corrupt device id must not be silently replaced")
        } catch CocoaError.fileReadCorruptFile {
            try expect(
                try String(contentsOf: file, encoding: .utf8) == "invalid",
                "a corrupt device id must remain available for diagnosis"
            )
        }

        try FileManager.default.removeItem(at: file)
        let legacyDeviceId = "0123456789abcdefabcd"
        let migrated = try KeychainStore.spotifyDeviceId(in: root) { legacyDeviceId }
        expect(migrated == legacyDeviceId, "the legacy device id must be preserved exactly")
        try expect(
            try String(contentsOf: file, encoding: .utf8) == legacyDeviceId,
            "the migrated device id must be persisted to the new file"
        )

        try FileManager.default.removeItem(at: file)
        do {
            _ = try KeychainStore.spotifyDeviceId(in: root) { "invalid" }
            fatalError("a corrupt legacy device id must not be replaced")
        } catch CocoaError.fileReadCorruptFile {
            expect(
                !FileManager.default.fileExists(atPath: file.path),
                "a corrupt legacy device id must not create a replacement file"
            )
        }

        enum LegacyReadError: Error { case denied }
        do {
            _ = try KeychainStore.spotifyDeviceId(in: root) { throw LegacyReadError.denied }
            fatalError("a failed legacy read must not generate a replacement")
        } catch LegacyReadError.denied {
            expect(
                !FileManager.default.fileExists(atPath: file.path),
                "a failed legacy read must leave the device id absent"
            )
        }

        let symlinkTarget = root.appendingPathComponent("device-id-target")
        try Data(legacyDeviceId.utf8).write(to: symlinkTarget)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: symlinkTarget)
        try expectFailure("a device id symlink must be rejected") {
            _ = try KeychainStore.spotifyDeviceId(in: root) {
                fatalError("a device id symlink must not trigger legacy migration")
            }
        }

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(
            atPath: file.path,
            withDestinationPath: root.appendingPathComponent("missing-target").path
        )
        try expectFailure("a dangling device id symlink must be rejected") {
            _ = try KeychainStore.spotifyDeviceId(in: root) {
                fatalError("a dangling symlink must not trigger legacy migration")
            }
        }

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try expectFailure("a non-file device id must be rejected") {
            _ = try KeychainStore.spotifyDeviceId(in: root) {
                fatalError("a non-file device id must not trigger legacy migration")
            }
        }

        let symlinkRoot = root.appendingPathComponent("symlink-root", isDirectory: true)
        let symlinkDirectoryTarget = root.appendingPathComponent("symlink-directory-target", isDirectory: true)
        try FileManager.default.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkDirectoryTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symlinkRoot.appendingPathComponent("Nanyin", isDirectory: true),
            withDestinationURL: symlinkDirectoryTarget
        )
        try expectFailure("a device id directory symlink must be rejected") {
            _ = try KeychainStore.spotifyDeviceId(in: symlinkRoot) {
                fatalError("a directory symlink must not trigger legacy migration")
            }
        }

        print("Keychain store tests passed")
    }

    private static func permissions(of url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        guard let permissions = value as? NSNumber else {
            fatalError("missing POSIX permissions for \(url.path)")
        }
        return permissions.intValue
    }

    private static func isValidDeviceId(_ id: String) -> Bool {
        id.utf8.count == 20
            && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func expectFailure(_ message: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
            fatalError(message)
        } catch {
            return
        }
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        guard try condition() else { fatalError(message) }
    }
}
