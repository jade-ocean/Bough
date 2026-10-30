import Foundation
import Combine

/// Drives the global search sheet: git grep over the worktree and
/// commit-message search across all branches, with debounced auto-run.
@MainActor
final class SearchModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case code
        case commits
    }

    @Published var tab: Tab = .code
    @Published var query = ""
    @Published var caseSensitive = false
    @Published var useRegex = false
    @Published var pathPrefix = ""
    @Published private(set) var codeResults: [GrepResult] = []
    @Published private(set) var commitResults: [Commit] = []
    @Published private(set) var isSearching = false
    @Published var errorText: String?

    private let repository: GitRepository
    private var searchTask: Task<Void, Never>?

    init(repository: GitRepository) {
        self.repository = repository
    }

    /// Debounced auto-search on any input change.
    func scheduleSearch() {
        searchTask?.cancel()
        guard !query.isEmpty else {
            codeResults = []
            commitResults = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    func run() async {
        let options = GrepOptions(caseSensitive: caseSensitive,
                                  useRegex: useRegex,
                                  pathPrefix: pathPrefix)
        isSearching = true
        defer { isSearching = false }
        do {
            switch tab {
            case .code:
                commitResults = []
                codeResults = try await repository.grep(query, options: options)
                errorText = nil
            case .commits:
                codeResults = []
                commitResults = try await repository.searchCommits(query)
                errorText = nil
            }
        } catch {
            // git grep exits non-zero for regex errors and "no match" alike.
            errorText = query.isEmpty ? nil : error.localizedDescription
        }
    }
}
