import Foundation
import SwiftData

/// Recent repository entry (SwiftData). `path` is the business key
/// (dedup handled in code - no @Attribute(.unique) to keep schema portable).
@Model
final class RepositoryRecord {
    /// Worktree root absolute path (symlinks resolved).
    var path: String
    /// Display name (root folder name).
    var name: String
    var addedAt: Date
    var lastOpenedAt: Date

    init(path: String, name: String, addedAt: Date = .now, lastOpenedAt: Date = .now) {
        self.path = path
        self.name = name
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
    }
}
