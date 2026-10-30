import Foundation
import Combine

/// Branch tree + remote registry for one repository.
@MainActor
final class BranchModel: ObservableObject {
    @Published private(set) var local: [Branch] = []
    @Published private(set) var remote: [Branch] = []
    @Published private(set) var remotes: [RemoteInfo] = []
    @Published private(set) var isLoading = false

    private let repository: GitRepository

    init(repository: GitRepository) {
        self.repository = repository
    }

    var currentBranch: Branch? {
        local.first(where: \.isCurrent)
    }

    /// Remote branches grouped by remote name, sorted by name within group.
    var remoteGroups: [(name: String, branches: [Branch])] {
        let grouped = Dictionary(grouping: remote) { branch -> String in
            branch.name.split(separator: "/").first.map(String.init) ?? branch.name
        }
        return grouped.keys.sorted().map { key in
            (key, (grouped[key] ?? []).sorted { $0.name < $1.name })
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await repository.branches()
            local = result.local.sorted { $0.name < $1.name }
            remote = result.remote
                .filter { !$0.name.contains("HEAD") }
                .sorted { $0.name < $1.name }
            remotes = try await repository.remotes()
        } catch {
            Log.git.error("branch load failed: \(String(describing: error), privacy: .public)")
        }
    }
}
