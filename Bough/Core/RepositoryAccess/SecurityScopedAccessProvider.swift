import Foundation

/// Reserved skeleton for the future sandboxed mode: security-scoped bookmarks.
/// Not wired up; see AGENTS/spec - enabled only when sandboxing becomes a requirement.
struct SecurityScopedAccessProvider: RepositoryAccessProvider {
    enum ProviderError: LocalizedError {
        case notImplemented

        var errorDescription: String? {
            "SecurityScopedAccessProvider is a reserved skeleton (non-sandboxed phase)."
        }
    }

    func resolveWorkTreeRoot(at path: String) throws -> URL {
        throw ProviderError.notImplemented
    }

    func resolveGitDirectory(forWorkTreeRoot root: URL) throws -> URL {
        throw ProviderError.notImplemented
    }

    func dataForFile(at absoluteURL: URL) throws -> Data {
        throw ProviderError.notImplemented
    }

    func writeData(_ data: Data, to absoluteURL: URL) throws {
        throw ProviderError.notImplemented
    }
}
