import Foundation
import Combine

/// Drives the multi-repository overview window: scan recent repos,
/// then batch fetch / pull with per-row outcome display.
@MainActor
final class MultiRepoModel: ObservableObject {
    enum RowState: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    struct Row: Identifiable {
        let path: String
        var snapshot: MultiRepoBatch.RepoSnapshot?
        var state: RowState = .idle

        var id: String { path }
        var name: String {
            snapshot?.name ?? URL(fileURLWithPath: path).lastPathComponent
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isBusy = false
    /// Confirmation for the destructive-ish batch pull.
    @Published var showsPullConfirm = false

    private var gitBinary: String?

    /// Seed from the recents store; dedupe by path, most recent first.
    func seed(paths: [String]) {
        guard rows.isEmpty else { return }
        rows = paths.map { Row(path: $0) }
    }

    func scan() async {
        isBusy = true
        defer { isBusy = false }
        markAll(.working)
        let paths = rows.map(\.path)
        let snapshots = await MultiRepoBatch.scan(paths: paths, gitBinary: gitBinary)
        for row in rows.indices {
            if let snapshot = snapshots.first(where: { $0.path == rows[row].path }) {
                rows[row].snapshot = snapshot
                rows[row].state = snapshot.isValid
                    ? .done("扫描完成") : .failed(snapshot.message ?? "无效仓库")
            }
        }
    }

    func fetchAll() async {
        await runBatch("fetch 完成") { try await $0.fetch() }
    }

    func pullAll() async {
        let strategy = AppPreferences.defaultPullStrategy
        await runBatch("pull（\(strategy.rawValue)）完成") { try await $0.pull(strategy: strategy) }
    }

    private func runBatch(_ successText: String,
                          _ operation: @escaping (GitRepository) async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        for row in rows.indices where rows[row].snapshot?.isValid == true {
            rows[row].state = .working
        }
        let validPaths = rows.filter { $0.snapshot?.isValid == true }.map(\.path)
        let outcomes = await MultiRepoBatch.runCustom(paths: validPaths,
                                                      gitBinary: gitBinary,
                                                      successText: successText,
                                                      operation)
        for row in rows.indices {
            if let outcome = outcomes.first(where: { $0.path == rows[row].path }) {
                rows[row].state = outcome.succeeded ? .done(outcome.message) : .failed(outcome.message)
            }
        }
        await scan()
    }

    func open(row: Row) {
        PendingOpenRouter.shared.pendingPath = row.path
    }

    private func markAll(_ state: RowState) {
        for row in rows.indices {
            rows[row].state = state
        }
    }
}
