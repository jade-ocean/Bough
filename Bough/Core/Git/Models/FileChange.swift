import Foundation

/// A file changed by a commit (or in the working copy).
struct FileChange: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case typechange = "T"
        case untracked = "?"
    }

    let path: String
    let originalPath: String?
    let kind: Kind
    /// numstat "-" markers -> binary content.
    let isBinary: Bool

    var id: String { path }
    var displayPath: String { originalPath.map { "\($0) → \(path)" } ?? path }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "heic", "bmp", "icns",
    ]

    var isImage: Bool {
        Self.imageExtensions.contains(path.split(separator: ".").last.map { $0.lowercased() } ?? "")
    }

    /// Bridge to the status-side enum used by row views.
    var asFileStatus: FileStatus {
        switch kind {
        case .added: return .added
        case .modified: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .copied: return .copied
        case .typechange: return .typechange
        case .untracked: return .untracked
        }
    }
}
