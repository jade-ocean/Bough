import Foundation

/// Multi-repository batch operations (P2): concurrent status scan and
/// fetch/pull across the recent-repositories list. Each repository has its
/// own actor executor, so per-repo work runs in parallel without contention.
enum MultiRepoBatch {

    struct RepoSnapshot: Identifiable, Equatable, Sendable {
        let path: String
        let name: String
        var isValid = false
        var branch: String?
        var ahead = 0
        var behind = 0
        var dirtyCount = 0
        /// Short human-readable note (e.g. not a repo / scan error).
        var message: String?

        var id: String { path }
    }

    struct OpOutcome: Equatable, Sendable {
        let path: String
        let succeeded: Bool
        let message: String
    }

    /// Snapshot every path concurrently; invalid paths come back with
    /// isValid=false and a note instead of failing the batch.
    static func scan(paths: [String], gitBinary: String? = nil) async -> [RepoSnapshot] {
        await withTaskGroup(of: RepoSnapshot.self) { group in
            for path in paths {
                group.addTask {
                    await scanOne(path: path, gitBinary: gitBinary)
                }
            }
            var results: [RepoSnapshot] = []
            for await snapshot in group {
                results.append(snapshot)
            }
            return results.sorted { $0.name < $1.name }
        }
    }

    private static func scanOne(path: String, gitBinary: String?) async -> RepoSnapshot {
        var snapshot = RepoSnapshot(path: path,
                                    name: URL(fileURLWithPath: path).lastPathComponent)
        do {
            let root = try RepositoryLocator.locateWorkTreeRoot(at: path)
            let repo = try GitRepository(root: root, gitBinary: gitBinary)
            let status = try await repo.status()
            let branches = try await repo.branches()
            snapshot.isValid = true
            snapshot.branch = status.branch
            snapshot.ahead = branches.local.first(where: \.isCurrent)?.ahead ?? 0
            snapshot.behind = branches.local.first(where: \.isCurrent)?.behind ?? 0
            snapshot.dirtyCount = status.entries.count
        } catch {
            snapshot.message = error.localizedDescription
        }
        return snapshot
    }

    /// Fetch every valid repository concurrently; one failure doesn't stop the rest.
    static func fetchAll(paths: [String], gitBinary: String? = nil) async -> [OpOutcome] {
        await runCustom(paths: paths, gitBinary: gitBinary, successText: "fetch 完成") {
            try await $0.fetch()
        }
    }

    /// Pull (merge strategy) every valid repository concurrently.
    static func pullAll(paths: [String], strategy: GitRepository.PullStrategy,
                        gitBinary: String? = nil) async -> [OpOutcome] {
        await runCustom(paths: paths, gitBinary: gitBinary, successText: "pull 完成") {
            try await $0.pull(strategy: strategy)
        }
    }

    /// Generic concurrent runner exposed for model-layer composition.
    static func runCustom(paths: [String],
                          gitBinary: String?,
                          successText: String,
                          _ operation: @escaping (GitRepository) async throws -> Void) async -> [OpOutcome] {
        await runOperation(paths: paths, gitBinary: gitBinary) { repo in
            try await operation(repo)
            return successText
        }
    }

    private static func runOperation(paths: [String],
                                     gitBinary: String?,
                                     _ operation: @escaping (GitRepository) async throws -> String) async -> [OpOutcome] {
        await withTaskGroup(of: OpOutcome.self) { group in
            for path in paths {
                group.addTask {
                    do {
                        let root = try RepositoryLocator.locateWorkTreeRoot(at: path)
                        let repo = try GitRepository(root: root, gitBinary: gitBinary)
                        let message = try await operation(repo)
                        return OpOutcome(path: path, succeeded: true, message: message)
                    } catch {
                        return OpOutcome(path: path, succeeded: false,
                                         message: error.localizedDescription)
                    }
                }
            }
            var results: [OpOutcome] = []
            for await outcome in group {
                results.append(outcome)
            }
            return results.sorted { $0.path < $1.path }
        }
    }
}
