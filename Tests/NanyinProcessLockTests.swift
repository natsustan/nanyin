import Foundation

@main
private enum NanyinProcessLockTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var firstLock = try NanyinProcessLock.acquire(in: root)
        expect(firstLock != nil, "the first process must acquire the instance lock")
        try expect(
            try NanyinProcessLock.acquire(in: root) == nil,
            "a concurrent process must not acquire the instance lock"
        )

        firstLock = nil
        try expect(
            try NanyinProcessLock.acquire(in: root) != nil,
            "the instance lock must become available after its owner exits"
        )

        print("Nanyin process lock tests passed")
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) rethrows {
        guard try condition() else { fatalError(message) }
    }
}
