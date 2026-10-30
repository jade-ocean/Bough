import Foundation
import SwiftData

/// Persistence operations for recent repositories (upsert / remove).
/// MainActor-bound because ModelContext is not thread-safe.
@MainActor
final class RecentRepositoriesStore: ObservableObject {
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Record (or refresh) a repository entry after a successful open, keyed by path.
    func recordOpen(root: URL) {
        let path = root.path
        let name = root.lastPathComponent
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<RepositoryRecord>(
            predicate: #Predicate { $0.path == path }
        )

        do {
            if let existing = try context.fetch(descriptor).first {
                existing.lastOpenedAt = .now
            } else {
                context.insert(RepositoryRecord(path: path, name: name))
            }
            try context.save()
            Log.repository.info("opened repository: \(path, privacy: .public)")
        } catch {
            Log.repository.error("recordOpen failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Remove a recent entry (never deletes repository content on disk).
    func remove(_ record: RepositoryRecord) {
        modelContainer.mainContext.delete(record)
        do {
            try modelContainer.mainContext.save()
        } catch {
            Log.repository.error("remove failed: \(String(describing: error), privacy: .public)")
        }
    }
}
