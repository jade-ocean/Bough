import Foundation

/// Non-sandboxed implementation: direct path access.
/// All discovery/validation lives in RepositoryLocator (pure, unit-testable).
struct DirectPathAccessProvider: RepositoryAccessProvider {
    func resolveWorkTreeRoot(at path: String) throws -> URL {
        try RepositoryLocator.locateWorkTreeRoot(at: path)
    }

    func resolveGitDirectory(forWorkTreeRoot root: URL) throws -> URL {
        try RepositoryLocator.resolveGitDirectory(inWorkTree: root)
    }

    func dataForFile(at absoluteURL: URL) throws -> Data {
        try Data(contentsOf: absoluteURL)
    }

    func writeData(_ data: Data, to absoluteURL: URL) throws {
        try data.write(to: absoluteURL, options: .atomic)
    }
}
