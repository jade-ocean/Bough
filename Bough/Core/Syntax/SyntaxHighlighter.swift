import Foundation

/// Supported highlight languages (lightweight line-oriented highlighting).
enum SyntaxLanguage: String, CaseIterable, Sendable {
    case swift
    case javaScript
    case python
    case go
    case rust
    case markdown
    case plain

    static func detect(fileName: String) -> SyntaxLanguage {
        let ext = fileName.split(separator: ".").last.map { $0.lowercased() } ?? ""
        switch ext {
        case "swift": return .swift
        case "js", "ts", "jsx", "tsx", "mjs", "cjs": return .javaScript
        case "py": return .python
        case "go": return .go
        case "rs": return .rust
        case "md", "markdown": return .markdown
        default: return .plain
        }
    }
}

/// Token classes rendered by the diff views.
enum TokenKind: Equatable, Sendable {
    case plain
    case keyword
    case string
    case comment
    case number
    case heading
    case fence
    case quote
    case listMarker
    case link
}

struct HighlightToken: Equatable, Sendable {
    let text: String
    let kind: TokenKind
}

enum SyntaxHighlighter {
    /// State carried across consecutive lines (block comments, strings, fences).
    struct State: Equatable, Sendable {
        var inBlockComment = false
        var stringDelimiter: Character?
        /// Python/Swift triple-quoted strings.
        var tripleDelimiter: [Character]?
        var inCodeFence = false
    }

    static func highlight(_ line: String,
                          language: SyntaxLanguage,
                          state: inout State) -> [HighlightToken] {
        if language == .markdown { return highlightMarkdown(line, state: &state) }
        if language == .plain || line.isEmpty {
            state.stringDelimiter = nil
            return [HighlightToken(text: line, kind: .plain)]
        }
        var tokens: [HighlightToken] = []
        var current = ""
        var kind: TokenKind = .plain

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(HighlightToken(text: current, kind: kind))
            current = ""
        }
        func emit(_ text: String, _ tokenKind: TokenKind) {
            flush()
            if !text.isEmpty { tokens.append(HighlightToken(text: text, kind: tokenKind)) }
        }

        let spec = spec(for: language)
        var index = line.startIndex
        while index < line.endIndex {
            let rest = String(line[index...])

            // Block comment continuation
            if state.inBlockComment {
                if let close = spec.blockCommentClose, let range = rest.range(of: close) {
                    let part = String(rest[..<range.lowerBound])
                    index = line.index(index, offsetBy: part.count, limitedBy: line.endIndex) ?? line.endIndex
                    // Skip the whole close delimiter, not just one character.
                    if index < line.endIndex {
                        index = line.index(index, offsetBy: close.count, limitedBy: line.endIndex) ?? line.endIndex
                    }
                    emit(part + close, .comment)
                    state.inBlockComment = false
                } else {
                    emit(rest, .comment)
                    index = line.endIndex
                }
                continue
            }
            // String continuation
            if let delimiter = state.stringDelimiter {
                let consumed = consumeString(String(line[index...]), delimiter: delimiter, triple: false)
                index = line.index(index, offsetBy: consumed.charactersConsumed, limitedBy: line.endIndex) ?? line.endIndex
                if consumed.closed {
                    emit(consumed.text, .string)
                    state.stringDelimiter = nil
                } else {
                    emit(consumed.text, .string)
                }
                continue
            }
            // Triple-string continuation (python """ / ''', swift """)
            if let triple = state.tripleDelimiter {
                let delimiter = String(triple)
                if let range = rest.range(of: delimiter) {
                    let part = String(rest[..<range.lowerBound])
                    index = line.index(index, offsetBy: part.count, limitedBy: line.endIndex) ?? line.endIndex
                    if index < line.endIndex {
                        index = line.index(index, offsetBy: triple.count, limitedBy: line.endIndex) ?? line.endIndex
                    }
                    emit(part + delimiter, .string)
                    state.tripleDelimiter = nil
                } else {
                    emit(rest, .string)
                    index = line.endIndex
                }
                continue
            }

            // Line comments
            if let commentToken = spec.lineComments.first(where: { rest.hasPrefix($0) }) {
                emit(current.isEmpty ? "" : current, kind)
                emit(String(line[index...]), .comment)
                return tokens
            }
            // Block comment open
            if let open = spec.blockCommentOpen, rest.hasPrefix(open) {
                emit(current, kind)
                current = open
                kind = .comment
                state.inBlockComment = true
                index = line.index(index, offsetBy: open.count, limitedBy: line.endIndex) ?? line.endIndex
                continue
            }
            // Triple-string open (python)
            if spec.supportsTripleStrings {
                var opened = false
                for triple in ["\"\"\"", "'''"] where rest.hasPrefix(triple) {
                    emit(current, kind)
                    current = triple
                    kind = .string
                    state.tripleDelimiter = Array(triple)
                    index = line.index(index, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
                    opened = true
                    break
                }
                if opened { continue }
            }
            // Single-line string open
            if let delim = spec.stringDelimiters.first(where: { rest.first == $0 }) {
                emit(current, kind)
                let consumed = consumeString(rest, delimiter: delim, triple: false)
                emit(consumed.text, .string)
                if !consumed.closed { state.stringDelimiter = delim }
                index = line.index(index, offsetBy: consumed.charactersConsumed, limitedBy: line.endIndex) ?? line.endIndex
                continue
            }
            // Word / number
            let ch = line[index]
            if ch.isLetter || ch == "_" {
                var word = ""
                var cursor = index
                while cursor < line.endIndex,
                      line[cursor].isLetter || line[cursor].isNumber || line[cursor] == "_" {
                    word.append(line[cursor])
                    cursor = line.index(after: cursor)
                }
                let tokenKind: TokenKind = spec.keywords.contains(word) ? .keyword : .plain
                emit(word, tokenKind)
                index = cursor
                continue
            }
            if ch.isNumber {
                var number = ""
                var cursor = index
                while cursor < line.endIndex,
                      line[cursor].isNumber || "abcdefABCDEFxXoO._".contains(line[cursor]) {
                    number.append(line[cursor])
                    cursor = line.index(after: cursor)
                }
                emit(number, .number)
                index = cursor
                continue
            }
            current.append(ch)
            index = line.index(after: index)
        }
        flush()
        return tokens
    }
}


extension SyntaxHighlighter {
    struct LanguageSpec {
        let lineComments: [String]
        let blockCommentOpen: String?
        let blockCommentClose: String?
        let stringDelimiters: [Character]
        let keywords: Set<String>
        let supportsTripleStrings: Bool
    }

    static func spec(for language: SyntaxLanguage) -> LanguageSpec {
        switch language {
        case .swift:
            return LanguageSpec(
                lineComments: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
                stringDelimiters: ["\""],
                keywords: Set(["associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
                               "func", "import", "init", "inout", "internal", "let", "open", "operator",
                               "private", "precedencegroup", "protocol", "public", "rethrows", "static",
                               "struct", "subscript", "typealias", "var", "break", "case", "catch",
                               "continue", "default", "defer", "do", "else", "fallthrough", "for",
                               "guard", "if", "in", "repeat", "return", "throw", "switch", "try",
                               "where", "while", "as", "false", "is", "nil", "self", "super", "throws",
                               "true", "try", "async", "await", "some", "any"]),
                supportsTripleStrings: true)
        case .javaScript:
            return LanguageSpec(
                lineComments: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
                stringDelimiters: ["\"", "'", "`"],
                keywords: Set(["async", "await", "break", "case", "catch", "class", "const", "continue",
                               "debugger", "default", "delete", "do", "else", "enum", "export", "extends",
                               "false", "finally", "for", "function", "if", "implements", "import", "in",
                               "instanceof", "interface", "let", "new", "null", "of", "private", "protected",
                               "public", "return", "static", "super", "switch", "this", "throw", "true",
                               "try", "typeof", "undefined", "var", "void", "while", "with", "yield"]),
                supportsTripleStrings: false)
        case .python:
            return LanguageSpec(
                lineComments: ["#"], blockCommentOpen: nil, blockCommentClose: nil,
                stringDelimiters: ["\"", "'"],
                keywords: Set(["and", "as", "assert", "async", "await", "break", "class", "continue",
                               "def", "del", "elif", "else", "except", "False", "finally", "for", "from",
                               "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
                               "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"]),
                supportsTripleStrings: true)
        case .go:
            return LanguageSpec(
                lineComments: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
                stringDelimiters: ["\"", "'"],
                keywords: Set(["break", "case", "chan", "const", "continue", "default", "defer", "else",
                               "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                               "map", "package", "range", "return", "select", "struct", "switch", "type",
                               "var", "nil", "true", "false"]),
                supportsTripleStrings: false)
        case .rust:
            return LanguageSpec(
                lineComments: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
                stringDelimiters: ["\""],
                keywords: Set(["as", "async", "await", "break", "const", "continue", "crate", "dyn",
                               "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let",
                               "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
                               "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
                               "use", "where", "while"]),
                supportsTripleStrings: false)
        default:
            return LanguageSpec(lineComments: [], blockCommentOpen: nil, blockCommentClose: nil,
                                stringDelimiters: [], keywords: [], supportsTripleStrings: false)
        }
    }
}

extension SyntaxHighlighter {
    /// Scan a (possibly escaped) string body starting at the opening delimiter.
    /// Returns consumed text and whether the string closed on this line.
    static func consumeString(_ rest: String, delimiter: Character, triple: Bool) -> (text: String, charactersConsumed: Int, closed: Bool) {
        var consumed = ""
        var count = 0
        var iterator = rest.makeIterator()
        var previous: Character?
        // First char is the opening delimiter.
        if let first = iterator.next() {
            consumed.append(first)
            count += 1
            if first != delimiter { return (consumed, count, false) }
        }
        while let ch = iterator.next() {
            consumed.append(ch)
            count += 1
            if ch == "\\" {
                if let escaped = iterator.next() {
                    consumed.append(escaped)
                    count += 1
                }
                continue
            }
            if ch == delimiter && previous != "\\" {
                return (consumed, count, true)
            }
            previous = ch
        }
        return (consumed, count, false)
    }

    /// Markdown: heading / fence / quote / list / link, line-based.
    static func highlightMarkdown(_ line: String, state: inout State) -> [HighlightToken] {
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            state.inCodeFence.toggle()
            return [HighlightToken(text: line, kind: .fence)]
        }
        if state.inCodeFence {
            return [HighlightToken(text: line, kind: .plain)]
        }
        if line.hasPrefix("#") {
            return [HighlightToken(text: line, kind: .heading)]
        }
        if line.hasPrefix(">") {
            return [HighlightToken(text: line, kind: .quote)]
        }
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return [HighlightToken(text: String(marker), kind: .listMarker),
                    HighlightToken(text: String(line.dropFirst(2)), kind: .plain)]
        }
        if let range = line.range(of: "http://") ?? line.range(of: "https://") {
            return [HighlightToken(text: String(line[..<range.lowerBound]), kind: .plain),
                    HighlightToken(text: String(line[range.lowerBound...]), kind: .link)]
        }
        return [HighlightToken(text: line, kind: .plain)]
    }
}
