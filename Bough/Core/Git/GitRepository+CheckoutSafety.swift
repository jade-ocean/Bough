import Foundation

/// Checkout flow that survives uncommitted changes (working-copy safety).
extension GitRepository {

    enum CheckoutOutcome: Equatable, Sendable {
        /// Branch switched; no stash was needed.
        case switched
        /// Branch switched and changes restored; a conflicting restore left
        /// the stash in place at stash@{0}.
        case switchedWithRetainedStash
    }

    /// Switch branches, auto-stashing uncommitted work when git refuses.
    ///
    /// 1. plain `git checkout <branch>` (git carries compatible changes over)
    /// 2. on "would be overwritten by checkout": `git stash push -u`,
    ///    checkout, `git stash apply --index`; drop the stash when the apply
    ///    is clean, retain it (and report) on conflict.
    func checkoutBranchPreservingChanges(_ name: String,
                                         autoStashMessage: String) async throws -> CheckoutOutcome {
        let first = try await run(["checkout", "-q", name])
        if first.succeeded { return .switched }

        let dirtyTreeMarkers = ["would be overwritten by checkout",
                                "Please commit your changes or stash them"]
        guard dirtyTreeMarkers.contains(where: { first.stderr.contains($0) }) else {
            throw GitError.executionFailed(command: "checkout \(name)",
                                           exitCode: first.exitCode,
                                           stderr: first.stderr)
        }

        try await stashPush(message: autoStashMessage, includeUntracked: true)
        try await runOrThrow(["checkout", "-q", name])

        guard let top = try await stashList().first else { return .switched }
        do {
            try await stashApply(top.selector, restoreIndex: false)
            try await stashDrop(top.selector)
            return .switched
        } catch {
            return .switchedWithRetainedStash
        }
    }
}
