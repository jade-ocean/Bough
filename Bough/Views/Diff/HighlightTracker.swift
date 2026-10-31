import SwiftUI

/// Highlights diff lines while carrying tokenizer state across consecutive
/// lines (old/new columns tracked independently for side-by-side).
/// Reference type so row views can share one instance per rendered file.
final class HighlightTracker {
    private let language: SyntaxLanguage
    private var oldState = SyntaxHighlighter.State()
    private var newState = SyntaxHighlighter.State()

    init(language: SyntaxLanguage) {
        self.language = language
    }

    /// Advance whichever file side this line belongs to and return colored text.
    func attributed(_ line: DiffLine) -> AttributedString {
        var tokens: [HighlightToken]
        switch line.kind {
        case .added:
            tokens = SyntaxHighlighter.highlight(line.text, language: language, state: &newState)
        case .deleted:
            tokens = SyntaxHighlighter.highlight(line.text, language: language, state: &oldState)
        case .context:
            // Context exists in both files: both sides progress.
            tokens = SyntaxHighlighter.highlight(line.text, language: language, state: &newState)
            _ = SyntaxHighlighter.highlight(line.text, language: language, state: &oldState)
        }
        var result = AttributedString()
        for token in tokens {
            var segment = AttributedString(token.text)
            segment.foregroundColor = Self.color(for: token.kind)
            result += segment
        }
        if result.characters.isEmpty {
            result = AttributedString(" ")
        }
        return result
    }

    static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .plain: return .primary
        case .keyword: return .purple
        case .string: return .red
        case .comment: return .green
        case .number: return .blue
        case .heading: return .pink
        case .fence: return .orange
        case .quote: return .gray
        case .listMarker: return .orange
        case .link: return .cyan
        }
    }
}
