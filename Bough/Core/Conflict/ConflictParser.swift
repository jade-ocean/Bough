import Foundation

/// Parses git conflict markers in a working-copy file into segments,
/// tracks per-block resolution choices, and rebuilds the resolved text.
///
/// Supports the default style and diff3 (`|||||||` base section is captured
/// and displayed but not part of ours/theirs/both output).
enum ConflictParser {
    enum Segment: Equatable {
        case plain(String)
        case conflict(ConflictBlock)
    }

    struct ConflictBlock: Equatable {
        var ours: [String]
        var theirs: [String]
        /// diff3 base section (informational).
        var base: [String]
        /// Resolution chosen by the user; nil = unresolved.
        var choice: Choice?

        enum Choice: String, Equatable, CaseIterable, Sendable {
            case ours = "ours"
            case theirs = "theirs"
            case both = "both"
        }
    }

    struct ParseResult: Equatable {
        var segments: [Segment]

        var blocks: [ConflictBlock] {
            segments.compactMap {
                if case .conflict(let block) = $0 { return block }
                return nil
            }
        }

        var unresolvedCount: Int {
            blocks.filter { $0.choice == nil }.count
        }

        var allResolved: Bool {
            unresolvedCount == 0 && !blocks.isEmpty
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> ParseResult {
        guard !text.isEmpty else { return ParseResult(segments: []) }
        var segments: [Segment] = []
        var plainBuffer: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("<<<<<<<") {
                if !plainBuffer.isEmpty {
                    segments.append(.plain(plainBuffer.joined(separator: "\n")))
                    plainBuffer = []
                }
                var ours: [String] = []
                var base: [String] = []
                var theirs: [String] = []
                var side: Int = 1 // 1 ours, 2 base, 3 theirs
                index += 1
                while index < lines.count {
                    let inner = lines[index]
                    if inner.hasPrefix("=======") {
                        side = 3
                    } else if inner.hasPrefix("|||||||") {
                        side = 2
                    } else if inner.hasPrefix(">>>>>>>") {
                        index += 1
                        break
                    } else {
                        switch side {
                        case 1: ours.append(inner)
                        case 2: base.append(inner)
                        default: theirs.append(inner)
                        }
                    }
                    index += 1
                }
                segments.append(.conflict(ConflictBlock(ours: ours, theirs: theirs, base: base, choice: nil)))
                continue
            }
            plainBuffer.append(line)
            index += 1
        }
        if !plainBuffer.isEmpty {
            segments.append(.plain(plainBuffer.joined(separator: "\n")))
        }
        return ParseResult(segments: segments)
    }

    // MARK: - Resolution

    /// Apply the block's choice; nil choice falls back to ours (defensive).
    static func resolve(_ block: ConflictBlock) -> [String] {
        switch block.choice {
        case .ours, nil: return block.ours
        case .theirs: return block.theirs
        case .both: return block.ours + block.theirs
        }
    }

    /// Rebuild full file text with every conflict replaced by its resolution.
    /// Always terminates with a newline when content is non-empty.
    static func resolvedText(_ result: ParseResult) -> String {
        var lines: [String] = []
        for segment in result.segments {
            switch segment {
            case .plain(let text):
                lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            case .conflict(let block):
                lines.append(contentsOf: resolve(block))
            }
        }
        guard !lines.isEmpty else { return "" }
        // Drop the trailing-newline artifact before normalizing the terminator.
        if lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
