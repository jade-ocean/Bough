import Foundation

/// A parsed commit (history rows, detail header, amend prefill).
struct Commit: Identifiable, Equatable, Hashable, Sendable {
    let sha: String
    let shortSha: String
    let authorName: String
    let authorEmail: String
    /// Unix timestamp (author date).
    let timestamp: Int
    let subject: String
    let body: String
    /// Parent shas (first parent first).
    var parents: [String] = []

    var id: String { sha }
}

/// user.name / user.email visible to a repository (repo config over global).
struct GitIdentity: Equatable, Sendable {
    let name: String?
    let email: String?

    var isComplete: Bool { !(name ?? "").isEmpty && !(email ?? "").isEmpty }
}

/// How commit signing follows configuration.
enum CommitSigning: String, CaseIterable, Sendable {
    /// Respect repo/global commit.gpgsign.
    case followConfig
    /// Force skip signing (--no-gpgsign).
    case forceOff
    /// Force signing (--gpgsign; uses the configured gpg/ssh program).
    case forceOn

    var arguments: [String] {
        switch self {
        case .followConfig: return []
        case .forceOff: return ["--no-gpgsign"]
        case .forceOn: return ["--gpgsign"]
        }
    }

    var label: String {
        switch self {
        case .followConfig: return "跟随仓库配置"
        case .forceOff: return "不签名"
        case .forceOn: return "签名"
        }
    }
}
