import Foundation

/// Branch, merge, rebase, and remote-sync operations (Phase 4).
extension GitRepository {

    // MARK: - Queries

    /// Local + remote branches with upstream track info.
    /// `%(upstream:track)` renders like "[ahead 1, behind 2]" or "[gone]".
    func branches() async throws -> (local: [Branch], remote: [Branch]) {
        let localResult = try await runOrThrow([
            "for-each-ref", "refs/heads",
            "--format=%(refname:short)%00%(objectname)%00%(HEAD)%00%(upstream:short)%00%(upstream:track)",
        ], serial: false)
        let remoteResult = try await runOrThrow([
            "for-each-ref", "refs/remotes", "--format=%(refname:short)%00%(objectname)",
        ], serial: false)

        func parse(_ output: String, isRemote: Bool) -> [Branch] {
            output.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 2, !fields[0].isEmpty else { return nil }
                let track = fields.count > 4 ? fields[4] : ""
                var ahead = 0, behind = 0
                if let match = track.range(of: #"ahead (\d+)"#, options: .regularExpression) {
                    ahead = Int(track[match].dropFirst("ahead ".count)) ?? 0
                }
                if let match = track.range(of: #"behind (\d+)"#, options: .regularExpression) {
                    behind = Int(track[match].dropFirst("behind ".count)) ?? 0
                }
                return Branch(
                    name: fields[0],
                    sha: fields[1],
                    isRemote: isRemote,
                    upstream: isRemote ? nil : fields.count > 3 ? fields[3] : nil,
                    ahead: ahead,
                    behind: behind,
                    isCurrent: isRemote ? false : fields.count > 2 && fields[2] == "*")
            }
        }
        return (parse(localResult.stdoutText, isRemote: false),
                parse(remoteResult.stdoutText, isRemote: true))
    }

    /// Entries from `git remote -v` (deduplicated fetch/push pairs).
    func remotes() async throws -> [RemoteInfo] {
        let result = try await runOrThrow(["remote", "-v"], serial: false)
        var order: [String] = []
        var fetch: [String: String] = [:]
        var push: [String: String] = [:]
        for line in result.stdoutText.split(separator: "\n") {
            // "<name>\t<url> (fetch|push)"
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            let name = String(parts[0])
            let urlPart = parts[1]
            let url = urlPart.split(separator: " ").first.map(String.init) ?? String(urlPart)
            if !order.contains(name) { order.append(name) }
            if urlPart.hasSuffix("(push)") {
                push[name] = url
            } else {
                fetch[name] = url
            }
        }
        return order.map { name in
            RemoteInfo(name: name, url: fetch[name] ?? "", pushURL: push[name])
        }
    }

    /// Validate a branch name via git itself.
    func isBranchNameValid(_ name: String) async -> Bool {
        let result = try? await run(["check-ref-format", "--branch", name], serial: false)
        return result?.succeeded == true
    }
    // MARK: - Branch mutations

    /// Create a branch; optionally point it at `startPoint` (defaults to HEAD)
    /// and check it out immediately.
    func createBranch(_ name: String, startPoint: String? = nil, checkout: Bool = false) async throws {
        var args = ["branch", name]
        if let startPoint { args.append(startPoint) }
        _ = try await runOrThrow(args)
        if checkout {
            try await checkoutBranch(name)
        }
    }

    func deleteBranch(_ name: String, force: Bool) async throws {
        _ = try await runOrThrow(["branch", force ? "-D" : "-d", name])
    }

    func renameBranch(_ oldName: String, to newName: String) async throws {
        _ = try await runOrThrow(["branch", "-m", oldName, newName])
    }

    func checkoutBranch(_ name: String) async throws {
        try await runOrThrow(["checkout", "-q", name])
    }

    // MARK: - Merge / rebase

    /// Merge a branch into the current one.
    func merge(_ branch: String) async throws {
        try await runOrThrow(["merge", "--no-edit", branch])
    }

    /// Rebase the current branch onto another branch.
    func rebase(onto branch: String) async throws {
        try await runOrThrow(["rebase", branch])
    }

    func rebaseAbort() async throws {
        try await runOrThrow(["rebase", "--abort"])
    }

    /// Continue a rebase; reuses the prepared message (no editor spawned).
    func rebaseContinue() async throws {
        try await runOrThrow(["-c", "core.editor=true", "rebase", "--continue"])
    }

    // MARK: - Remote sync

    /// Fetch all remotes (or one); prune deleted remote refs.
    func fetch(remote: String? = nil) async throws {
        let target = remote ?? "--all"
        try await runOrThrow(["fetch", "--prune", target], timeout: 300)
    }

    /// Pull with an explicit strategy (merge or rebase).
    enum PullStrategy: String, CaseIterable, Sendable {
        case merge = "merge"
        case rebase = "rebase"

        var label: String {
            switch self {
            case .merge: return "merge"
            case .rebase: return "rebase"
            }
        }
    }

    func pull(strategy: PullStrategy) async throws {
        switch strategy {
        case .merge:
            try await runOrThrow(["pull", "--no-rebase"], timeout: 300)
        case .rebase:
            try await runOrThrow(["pull", "--rebase"], timeout: 300)
        }
    }

    /// Push the current branch; sets upstream when missing.
    /// `forceWithLease` requires explicit confirmation at the UI layer.
    func push(remote: String = "origin", forceWithLease: Bool = false) async throws {
        var args = ["push"]
        if forceWithLease { args.append("--force-with-lease") }
        let branches = try await self.branches()
        let current = branches.local.first(where: \.isCurrent)
        if let current, current.upstream == nil || current.upstream?.isEmpty == true {
            args += ["-u", remote, current.name]
        } else {
            args.append(remote)
        }
        try await runOrThrow(args, timeout: 300)
    }

    /// Delete a branch on a remote.
    func deleteRemoteBranch(_ name: String, remote: String = "origin") async throws {
        let shortName = name.hasPrefix("\(remote)/") ? String(name.dropFirst(remote.count + 1)) : name
        try await runOrThrow(["push", remote, "--delete", shortName], timeout: 300)
    }

    // MARK: - Remote management

    func addRemote(name: String, url: String) async throws {
        try await runOrThrow(["remote", "add", name, url])
    }

    func removeRemote(name: String) async throws {
        try await runOrThrow(["remote", "remove", name])
    }

    /// Per-repo SSL configuration for self-signed certificates.
    func setSSLConfig(verify: Bool, caInfoPath: String?) async throws {
        if verify {
            _ = try await run(["config", "--unset", "http.sslVerify"])
        } else {
            try await runOrThrow(["config", "http.sslVerify", "false"])
        }
        if let caInfoPath {
            try await runOrThrow(["config", "http.sslCAInfo", caInfoPath])
        }
    }

    /// Read current per-repo SSL config (unset = verify on).
    func sslConfig() async -> (verify: Bool, caInfoPath: String?) {
        let verify = try? await configValue("http.sslVerify")
        let ca = try? await configValue("http.sslCAInfo")
        return (verify == nil || verify == "true", ca.flatMap { $0.isEmpty ? nil : $0 })
    }
}
