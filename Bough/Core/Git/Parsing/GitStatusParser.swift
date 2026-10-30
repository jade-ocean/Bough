import Foundation

/// Parser for `git status --porcelain=v2 -z --branch` output.
///
/// Wire format (NUL-separated records):
/// - `# branch.oid <sha>` / `# branch.head <name>` / `# branch.upstream <name>` / `# branch.ab +A -B`
/// - `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
/// - `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>` + NUL + `<origPath>`
enum GitStatusParser {
    static func parse(_ output: Data) throws -> GitStatus {
        var status = GitStatus()
        let records = output.split(separator: 0, omittingEmptySubsequences: true)
        var iterator = records.makeIterator()
        while let raw = iterator.next() {
            let record = String(decoding: raw, as: UTF8.self)
            let fields = record.split(separator: " ", maxSplits: .max, omittingEmptySubsequences: false)
            guard let tag = fields.first else { continue }
            switch tag {
            case "#":
                try parseBranchRecord(record, into: &status)
            case "1":
                status.entries.append(try parseOrdinaryRecord(fields))
            case "2":
                let entry = try parseOrdinaryRecord(fields)
                guard let originalPathToken = iterator.next() else {
                    throw GitError.unexpectedOutput("rename record missing original path: \(record)")
                }
                let origPath = String(decoding: originalPathToken, as: UTF8.self)
                status.entries.append(StatusEntry(
                    path: entry.path, indexStatus: entry.indexStatus,
                    worktreeStatus: entry.worktreeStatus, isUntracked: false,
                    originalPath: origPath))
            case "u":
                status.entries.append(parseUnmergedRecord(fields))
            case "?":
                let path = record.dropFirst(2)
                status.entries.append(StatusEntry(
                    path: String(path), indexStatus: nil, worktreeStatus: nil,
                    isUntracked: true, originalPath: nil))
            default:
                continue
            }
        }
        return status
    }
    // MARK: - Branch records

    private static func parseBranchRecord(_ record: String, into status: inout GitStatus) throws {
        // "# branch.head <name>" -> key = "branch.head"
        guard record.hasPrefix("# ") else {
            throw GitError.unexpectedOutput("malformed branch record: \(record)")
        }
        let body = record.dropFirst(2)
        guard let space = body.firstIndex(of: " ") else { return }
        let key = String(body[body.startIndex..<space])
        let value = String(body[body.index(after: space)...])

        switch key {
        case "branch.oid":
            // Unborn HEAD marker in git >= 2.x porcelain v2.
            if value == "(initial)" { status.isUnborn = true }
        case "branch.head":
            // Detached HEAD has no branch name.
            status.branch = value == "(detached)" ? nil : value
        case "branch.upstream":
            status.upstream = value == "(null)" ? nil : value
        case "branch.ab":
            // "+A -B"
            for token in value.split(separator: " ") {
                if token.hasPrefix("+"), let n = Int(token.dropFirst()) { status.ahead = n }
                if token.hasPrefix("-"), let n = Int(token.dropFirst()) { status.behind = n }
            }
        default:
            break
        }
    }

    // MARK: - Entry records

    /// Shared field layout for "1" and "2" records:
    /// `<tag> <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>` ("2" has <X><score> before path).
    private static func parseOrdinaryRecord(_ fields: [Substring]) throws -> StatusEntry {
        let xy = fields.count > 1 ? String(fields[1]) : ".."
        guard xy.count == 2 else {
            throw GitError.unexpectedOutput("bad XY field in: \(fields.joined(separator: " "))")
        }
        let indexChar = xy.first!
        let worktreeChar = xy.last!

        // "1" records: path at index 8; "2" records carry <X><score> at 8, path at 9.
        let pathIndex = fields[0] == "2" ? 9 : 8
        guard fields.count > pathIndex else {
            throw GitError.unexpectedOutput("short record: \(fields.joined(separator: " "))")
        }
        let path = String(fields[pathIndex])

        func status(_ ch: Character) -> FileStatus? {
            guard ch != "." else { return nil }
            return FileStatus(rawValue: ch)
        }
        return StatusEntry(
            path: path,
            indexStatus: status(indexChar),
            worktreeStatus: status(worktreeChar),
            isUntracked: false,
            originalPath: nil
        )
    }

    /// `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>`
    private static func parseUnmergedRecord(_ fields: [Substring]) -> StatusEntry {
        let xy = fields.count > 1 ? String(fields[1]) : "UU"
        let pathIndex = 10
        let path = fields.count > pathIndex ? String(fields[pathIndex]) : "?"
        return StatusEntry(
            path: path,
            indexStatus: nil,
            worktreeStatus: .conflicted,
            isUntracked: false,
            originalPath: nil
        )
    }
}
