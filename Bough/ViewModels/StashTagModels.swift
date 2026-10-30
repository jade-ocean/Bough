import Foundation
import Combine

/// Sidebar stash list (lifecycle ops live in WorkspaceModel).
@MainActor
final class StashModel: ObservableObject {
    @Published private(set) var entries: [StashEntry] = []

    private let repository: GitRepository

    init(repository: GitRepository) {
        self.repository = repository
    }

    func reload() async {
        do {
            entries = try await repository.stashList()
        } catch {
            // No stash yet is the common "error" path; treat as empty.
            entries = []
        }
    }
}

/// Sidebar tag list.
@MainActor
final class TagModel: ObservableObject {
    @Published private(set) var entries: [TagEntry] = []

    private let repository: GitRepository

    init(repository: GitRepository) {
        self.repository = repository
    }

    func reload() async {
        do {
            entries = try await repository.tagList()
        } catch {
            entries = []
        }
    }
}
