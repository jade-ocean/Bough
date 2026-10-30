import Foundation

/// Unified-diff text -> structured hunks/lines, plus side-by-side pairing.
enum DiffParser {
    /// Parses (possibly multi-file) unified diff output; returns one DiffFile per
    /// "diff --git" section. Binary sections yield DiffFile(isBinary: true).
    ///
    /// Path extraction takes the "b/" segment of the "diff --git" line; paths that
    /// themselves contain " b/" are a known, accepted limitation (git quotes those
    /// in practice, which we do not handle here).
    static func parse(_ text: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentPath: String?
        var currentIsBinary = false
        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentLines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        func flushHunk() {
            if let header = currentHeader, let parsed = parseHunkHeader(header) {
                hunks.append(DiffHunk(
                    oldStart: parsed.oldStart, oldCount: parsed.oldCount,
                    newStart: parsed.newStart, newCount: parsed.newCount,
                    section: parsed.section, lines: currentLines))
            }
            currentHeader = nil
            currentLines = []
        }
        func flushFile() {
            flushHunk()
            if let currentPath {
                files.append(DiffFile(hunks: hunks, isBinary: currentIsBinary, path: currentPath))
            }
            currentPath = nil
            currentIsBinary = false
            hunks = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                flushFile()
                currentPath = Self.pathFromGitLine(line)
            } else if line.hasPrefix("@@") {
                flushHunk()
                currentHeader = line
                if let parsed = parseHunkHeader(line) {
                    oldLine = parsed.oldStart
                    newLine = parsed.newStart
                }
            } else if line.hasPrefix("Binary files") {
                currentIsBinary = true
            } else if line.hasPrefix("---") || line.hasPrefix("+++")
                || line.hasPrefix("index ") || line.hasPrefix("new file mode")
                || line.hasPrefix("deleted file mode") || line.hasPrefix("old mode")
                || line.hasPrefix("new mode") || line.hasPrefix("similarity index")
                || line.hasPrefix("rename from") || line.hasPrefix("rename to")
                || line.hasPrefix("copy from") || line.hasPrefix("copy to") {
                continue
            } else if line.hasPrefix("\\ No newline") {
                continue
            } else if currentHeader != nil {
                let prefix = line.first ?? " "
                let body = String(line.dropFirst(prefix == " " || prefix == "+" || prefix == "-" ? 1 : 0))
                switch prefix {
                case " ":
                    currentLines.append(DiffLine(kind: .context, oldNumber: oldLine, newNumber: newLine, text: body))
                    oldLine += 1
                    newLine += 1
                case "+":
                    currentLines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: newLine, text: body))
                    newLine += 1
                case "-":
                    currentLines.append(DiffLine(kind: .deleted, oldNumber: oldLine, newNumber: nil, text: body))
                    oldLine += 1
                default:
                    // Anything else inside a hunk (e.g. stray empty line) is ignored.
                    break
                }
            }
        }
        flushFile()
        return files
    }

    // MARK: - Helpers

    /// "diff --git a/x/y.swift b/x/y.swift" -> "x/y.swift".
    static func pathFromGitLine(_ line: String) -> String? {
        guard let marker = line.range(of: " b/") else { return nil }
        let path = String(line[marker.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// `@@ -a,b +c,d @@ section` (counts may be omitted when 1).
    static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int,
                                                     newStart: Int, newCount: Int, section: String)? {
        guard line.hasPrefix("@@") else { return nil }
        let scanner = Scanner(string: line)
        guard scanner.scanString("@@") != nil,
              scanner.scanString("-") != nil,
              let oldStart = scanner.scanInt() else { return nil }
        var oldCount = 1
        if scanner.scanString(",") != nil {
            oldCount = scanner.scanInt() ?? 1
        }
        guard scanner.scanString("+") != nil,
              let newStart = scanner.scanInt() else { return nil }
        var newCount = 1
        if scanner.scanString(",") != nil {
            newCount = scanner.scanInt() ?? 1
        }
        // Skip the trailing "@@" before the (optional) function context.
        if scanner.scanString("@@") == nil {
            // tolerate a missing closing marker
        }
        let rest = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
        return (oldStart, oldCount, newStart, newCount, rest)
    }

    // MARK: - Hunk selection (partial staging)

    /// Rebuild a patch containing only the selected hunks (header preserved,
    /// hunks in ascending order). Returns nil for invalid/empty selections.
    static func patch(fromDiff diff: String, selecting hunkIndices: [Int]) -> String? {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstHunk = lines.firstIndex(where: { $0.hasPrefix("@@") }) else { return nil }
        let header = lines[0..<firstHunk].filter { !$0.isEmpty }

        var blocks: [[String]] = []
        var current: [String]?
        for line in lines[firstHunk...] {
            if line.hasPrefix("@@") {
                if let closed = current { blocks.append(closed) }
                current = [line]
            } else if current != nil {
                current?.append(line)
            }
        }
        if let open = current { blocks.append(open) }

        let wanted = Set(hunkIndices)
        guard !wanted.isEmpty, wanted.isSubset(of: 0..<blocks.count) else { return nil }
        var out = header
        for index in hunkIndices.sorted() {
            out.append(contentsOf: blocks[index])
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Side-by-side pairing

    struct SidePair: Equatable, Sendable {
        let left: DiffLine?
        let right: DiffLine?
    }

    /// Pair deletions/additions run-wise within each hunk (standard side-by-side
    /// alignment: context 1:1, then dels[i] against adds[i], remainder gets nil side).
    static func sideBySidePairs(_ hunk: DiffHunk) -> [SidePair] {
        var result: [SidePair] = []
        result.reserveCapacity(hunk.lines.count)
        var index = 0
        let lines = hunk.lines
        while index < lines.count {
            let line = lines[index]
            if line.kind == .context {
                result.append(SidePair(left: line, right: line))
                index += 1
                continue
            }
            var deletions: [DiffLine] = []
            var additions: [DiffLine] = []
            while index < lines.count && lines[index].kind == .deleted {
                deletions.append(lines[index])
                index += 1
            }
            while index < lines.count && lines[index].kind == .added {
                additions.append(lines[index])
                index += 1
            }
            let count = max(deletions.count, additions.count)
            for offset in 0..<count {
                result.append(SidePair(
                    left: offset < deletions.count ? deletions[offset] : nil,
                    right: offset < additions.count ? additions[offset] : nil))
            }
        }
        return result
    }
}
