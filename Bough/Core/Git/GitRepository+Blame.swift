import Foundation

/// One blamed line: final line number, authoring commit, raw content.
struct BlameEntry: Equatable, Sendable {
    let lineNumber: Int
    let sha: String
    let content: String
}

/// Commit metadata aggregated from blame porcelain blocks.
struct BlameCommit: Equatable, Sendable {
    let sha: String
    let author: String
    let timestamp: Int
    let summary: String
    /// Boundary commits sit outside the queried history (e.g. initial commit).
    let isBoundary: Bool
}

struct BlameResult: Equatable, Sendable {
    let entries: [BlameEntry]
    let commits: [String: BlameCommit]
}

/// `git blame --porcelain` parsing + typed wrapper (Phase: blame view).
extension GitRepository {

    /// Blame a file; `ref` empty blames the working tree.
    func blame(path: String, ref: String = "", ignoreWhitespace: Bool = true) async throws -> BlameResult {
        var args = ["blame", "--porcelain", "--root"]
        if ignoreWhitespace { args.append("-w") }
        if !ref.isEmpty { args.append(ref) }
        args += ["--", path]
        let result = try await runOrThrow(args, serial: false)
        return try GitBlameParser.parse(result.stdoutText)
    }
}

enum GitBlameParser {

    static func parse(_ text: String) throws -> BlameResult {
        var entries: [BlameEntry] = []
        var commits: [String: BlameCommit] = [:]
        // Per-block scratch state; metadata repeats only when the sha changes.
        var currentSha = ""
        var author = ""
        var timestamp = 0
        var summary = ""
        var isBoundary = false
        var expectedCount = 0
        var origLine = 0
        var finalLine = 0

        func flushCommit() {
            guard !currentSha.isEmpty, commits[currentSha] == nil else { return }
            commits[currentSha] = BlameCommit(sha: currentSha, author: author,
                                              timestamp: timestamp, summary: summary,
                                              isBoundary: isBoundary)
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("\t") {
                // Content line of the current entry.
                entries.append(BlameEntry(lineNumber: finalLine, sha: currentSha,
                                          content: String(line.dropFirst())))
                // Grouped entries share one header: consume remaining counts.
                expectedCount -= 1
                if expectedCount > 0 {
                    finalLine += 1
                }
                continue
            }
            // Header area for a (new) block.
            let fields = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard let tag = fields.first else { continue }
            if tag.count == 40, fields.count >= 3, Int(fields[1]) != nil {
                // New block header: "<sha> <origLine> <finalLine> [<groupCount>]"
                flushCommit()
                currentSha = tag
                origLine = Int(fields[1]) ?? 0
                finalLine = Int(fields[2]) ?? 0
                expectedCount = fields.count > 3 ? (Int(fields[3]) ?? 1) : 1
                isBoundary = false
                // Metadata may be omitted when repeating the previous sha.
                if commits[currentSha] == nil {
                    author = ""
                    timestamp = 0
                    summary = ""
                } else {
                    author = commits[currentSha]?.author ?? ""
                    timestamp = commits[currentSha]?.timestamp ?? 0
                    summary = commits[currentSha]?.summary ?? ""
                }
            } else {
                switch tag {
                case "author": author = String(line.dropFirst("author ".count))
                case "author-time": timestamp = Int(line.dropFirst("author-time ".count)) ?? 0
                case "summary": summary = String(line.dropFirst("summary ".count))
                case "boundary": isBoundary = true
                default: break // author-mail, author-tz, previous, filename ...
                }
            }
        }
        flushCommit()
        guard !entries.isEmpty else {
            throw GitError.unexpectedOutput("blame 输出没有任何行")
        }
        return BlameResult(entries: entries, commits: commits)
    }
}
