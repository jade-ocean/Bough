import Foundation

/// A tag from for-each-ref; annotated tags carry message + creator date.
struct TagEntry: Identifiable, Equatable, Sendable {
    let name: String
    /// Lightweight: target commit sha. Annotated: tag object sha.
    let sha: String
    let isAnnotated: Bool
    let message: String

    var id: String { name }
}

/// Tag management (Phase 5).
extension GitRepository {

    /// `git for-each-ref refs/tags` with objecttype distinguishing annotated tags.
    func tagList() async throws -> [TagEntry] {
        let result = try await runOrThrow([
            "for-each-ref", "refs/tags",
            "--format=%(refname:short)%00%(objectname)%00%(objecttype)%00%(contents:subject)",
        ], serial: false)
        return result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let fields = line.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 2, !fields[0].isEmpty else { return nil }
                return TagEntry(name: fields[0],
                                sha: fields[1],
                                isAnnotated: fields.count > 2 && fields[2] == "tag",
                                message: fields.count > 3 ? fields[3] : "")
            }
    }

    /// Lightweight tag pointing at `target` (defaults to HEAD).
    func createTag(_ name: String, target: String?) async throws {
        var args = ["tag", name]
        if let target { args.append(target) }
        _ = try await runOrThrow(args)
    }

    /// Annotated tag with message (stored in the tag object).
    func createAnnotatedTag(_ name: String, message: String, target: String?) async throws {
        var args = ["tag", "-a", name, "-m", message]
        if let target { args.append(target) }
        _ = try await runOrThrow(args)
    }

    func deleteTag(_ name: String) async throws {
        _ = try await runOrThrow(["tag", "-d", name])
    }

    /// Push a tag to a remote.
    func pushTag(_ name: String, remote: String = "origin") async throws {
        try await runOrThrow(["push", remote, name], timeout: 300)
    }

    /// Delete a tag on the remote.
    func deleteRemoteTag(_ name: String, remote: String = "origin") async throws {
        try await runOrThrow(["push", remote, ":refs/tags/\(name)"], timeout: 300)
    }
}
