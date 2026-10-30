import Foundation

/// A ref decoration shown on a history row (HEAD, branch, tag, remote).
struct RefDecoration: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case head
        case branch
        case remote
        case tag

        var label: String {
            switch self {
            case .head: return "HEAD"
            case .branch: return ""
            case .remote: return ""
            case .tag: return ""
            }
        }
    }

    let name: String
    let kind: Kind
    let isHead: Bool

    var id: String { "\(kind.rawValue):\(name)" }

    /// Parse from a full refname; nil for non-displayable refs.
    init?(refname: String, isHead: Bool) {
        if refname.hasPrefix("refs/heads/") {
            self.kind = .branch
            self.name = String(refname.dropFirst("refs/heads/".count))
        } else if refname.hasPrefix("refs/remotes/") {
            self.kind = .remote
            self.name = String(refname.dropFirst("refs/remotes/".count))
        } else if refname.hasPrefix("refs/tags/") {
            self.kind = .tag
            self.name = String(refname.dropFirst("refs/tags/".count))
        } else if refname == "HEAD" {
            self.kind = .head
            self.name = "HEAD"
        } else {
            return nil
        }
        self.isHead = isHead || self.kind == .head
    }
}
