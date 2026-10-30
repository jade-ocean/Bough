import Foundation

/// One `git reflog` entry (HEAD).
struct ReflogEntry: Identifiable, Equatable, Sendable {
    let sha: String
    let shortSha: String
    let timestamp: Int
    /// Selector like "HEAD@{3}".
    let selector: String
    /// Reflog message (operation), e.g. "reset: moving to HEAD~1".
    let operation: String

    var id: String { selector }
}

extension GitRepository {

    /// `git reflog -n 200 --pretty=format:%H%x1f%h%x1f%at%x1f%gD%x1f%gs%x1e`
    func reflog() async throws -> [ReflogEntry] {
        let result = try await runOrThrow([
            "reflog", "-n", "200",
            "--pretty=format:%H%x1f%h%x1f%at%x1f%gD%x1f%gs%x1e",
        ])
        return result.stdoutText
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { raw in
                let record = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count == 5 else { return nil }
                return ReflogEntry(sha: String(fields[0]),
                                   shortSha: String(fields[1]),
                                   timestamp: Int(fields[2]) ?? 0,
                                   selector: String(fields[3]),
                                   operation: String(fields[4]))
            }
    }

    /// Create a branch pointing at an arbitrary sha (reflog recovery).
    func createBranch(at sha: String, name: String) async throws {
        _ = try await runOrThrow(["branch", name, sha])
    }
}
