import Foundation

/// Locates a usable git binary.
///
/// Search order:
/// 1. directories on the process PATH (Homebrew git preferred in practice)
/// 2. well-known fallbacks, ending with Apple's shim /usr/bin/git
enum GitLocator {
    private static let fallbacks = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git",
    ]

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cached: String?

    /// First existing+executable candidate; verified lazily by the first real invocation.
    static func locate() throws -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached { return cached }

        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("git").path
                if fm.isExecutableFile(atPath: candidate) {
                    cached = candidate
                    return candidate
                }
            }
        }
        for candidate in fallbacks where fm.isExecutableFile(atPath: candidate) {
            cached = candidate
            return candidate
        }
        throw GitError.binaryNotFound
    }
}
