import Darwin
import Foundation

/// Keeps GUI and headless probe processes from opening dealer sessions at the
/// same time. The descriptor must remain open for the lifetime of the process.
final class NanyinProcessLock {
    private static let fileName = "com.nanyin.app.instance.lock"

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(
        in applicationSupportDirectory: URL? = nil
    ) throws -> NanyinProcessLock? {
        let directory = try applicationSupportDirectory ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let lockURL = directory.appendingPathComponent(fileName)
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw posixError()
        }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let error = posixError()
            close(descriptor)
            throw error
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid() else {
            close(descriptor)
            throw CocoaError(.fileReadCorruptFile)
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let error = posixError()
            close(descriptor)
            throw error
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                return nil
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return NanyinProcessLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
