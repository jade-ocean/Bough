import Foundation
import Combine

/// History list + graph layout + ref decorations for one repository.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var rows: [GraphRow] = []
    @Published private(set) var decorations: [String: [RefDecoration]] = [:]
    @Published private(set) var headSha: String?
    @Published private(set) var isLoading = false
    /// Client-side text match over sha/shortSha (git --grep covers subject/author).
    @Published var textQuery = ""

    @Published var filter = HistoryFilter() {
        didSet {
            guard filter != oldValue else { return }
            reloadTask?.cancel()
            reloadTask = Task { await reload() }
        }
    }

    private var reloadTask: Task<Void, Never>?
    private let repository: GitRepository

    init(repository: GitRepository) {
        self.repository = repository
    }

    var authors: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for row in rows {
            let name = row.commit.authorName
            if !name.isEmpty && seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names.sorted()
    }

    /// Rows filtered by the sha text query (message already filtered via --grep).
    var visibleRows: [GraphRow] {
        guard !textQuery.isEmpty else { return rows }
        let query = textQuery.lowercased()
        return rows.filter {
            $0.commit.sha.lowercased().contains(query)
                || $0.commit.subject.lowercased().contains(query)
        }
    }

    func decorations(for sha: String) -> [RefDecoration] {
        decorations[sha] ?? []
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let commits = try await repository.commits(filter: filter)
            // Lane assignment is pure CPU work on up to 2000 commits - keep it off main.
            rows = await Task.detached(priority: .userInitiated) {
                GraphLayouter.layout(commits)
            }.value
            decorations = try await repository.refDecorations()
            headSha = try await repository.headSha()
            let count = rows.count
            Log.git.info("history loaded: \(count) commits")
        } catch {
            Log.git.error("history load failed: \(String(describing: error), privacy: .public)")
            rows = []
        }
    }
}
