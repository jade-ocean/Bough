import Foundation

/// One `git grep` hit.
struct GrepResult: Identifiable, Equatable, Sendable {
    let file: String
    let line: Int
    let column: Int
    let text: String

    var id: String { "\(file):\(line):\(column)" }
}

/// Parameters for a code search run.
struct GrepOptions: Equatable, Sendable {
    var caseSensitive = false
    /// -E extended regex; otherwise -F fixed strings.
    var useRegex = false
    var pathPrefix = ""
}

/// Code search (git grep) + commit-message search (Phase 6).
extension GitRepository {

    /// `git grep -n --column -I [-i] [-E|-F] <pattern> [-- path]`
    /// Output lines: "file:line:column:text".
    func grep(_ pattern: String, options: GrepOptions, limit: Int = 500) async throws -> [GrepResult] {
        guard !pattern.isEmpty else { return [] }
        var args = ["grep", "-n", "--column", "-I"]
        if !options.caseSensitive { args.append("-i") }
        args.append(options.useRegex ? "-E" : "-F")
        args.append(pattern)
        if !options.pathPrefix.isEmpty {
            args += ["--", options.pathPrefix]
        }
        let result = try await run(args)
        // Exit 1 = no matches (a normal outcome, not an error); 2 = regex error.
        guard result.succeeded || result.exitCode == 1 else {
            throw GitError.executionFailed(command: args.joined(separator: " "),
                                           exitCode: result.exitCode, stderr: result.stderr)
        }
        return Self.parseGrep(result.stdoutText, limit: limit)
    }

    /// Parser split out for unit testing (file names may contain colons only in
    /// exotic cases; we take the LAST two colon groups as line/column).
    static func parseGrep(_ output: String, limit: Int) -> [GrepResult] {
        var results: [GrepResult] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4,
                  let lineNo = Int(parts[1]),
                  let column = Int(parts[2]) else { continue }
            results.append(GrepResult(file: String(parts[0]),
                                      line: lineNo,
                                      column: column,
                                      text: String(parts[3])))
            if results.count >= limit { break }
        }
        return results
    }

    /// Commit-message search over all branches (newest first).
    func searchCommits(_ text: String, limit: Int = 100) async throws -> [Commit] {
        guard !text.isEmpty else { return [] }
        let result = try await runOrThrow([
            "log", "--all", "-n", String(limit), "-i", "--grep", text,
            "--pretty=format:%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s%x1e",
        ])
        return GitLogParser.parseHistory(result.stdoutText)
    }
}
