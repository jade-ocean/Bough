import XCTest
@testable import Bough

final class SyntaxHighlighterTests: XCTestCase {

    func testDetectsLanguagesByExtension() {
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "Main.swift"), .swift)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "app.ts"), .javaScript)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "x.py"), .python)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "main.go"), .go)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "lib.rs"), .rust)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "README.md"), .markdown)
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "Makefile"), .plain)
    }

    func testSwiftKeywordsStringsComments() {
        var state = SyntaxHighlighter.State()
        let tokens = SyntaxHighlighter.highlight(
            "let x = \"hi\" // trailing",
            language: .swift, state: &state)
        XCTAssertTrue(tokens.contains(HighlightToken(text: "let", kind: .keyword)))
        XCTAssertTrue(tokens.contains(HighlightToken(text: "\"hi\"", kind: .string)))
        XCTAssertTrue(tokens.contains(HighlightToken(text: "// trailing", kind: .comment)))
    }

    func testBlockCommentCarriesAcrossLines() {
        var state = SyntaxHighlighter.State()
        _ = SyntaxHighlighter.highlight("/* start", language: .rust, state: &state)
        XCTAssertTrue(state.inBlockComment)
        let tokens = SyntaxHighlighter.highlight("middle */ let", language: .rust, state: &state)
        XCTAssertFalse(state.inBlockComment)
        XCTAssertTrue(tokens.contains { $0.kind == .comment && $0.text.hasPrefix("middle ") })
        XCTAssertTrue(tokens.contains(HighlightToken(text: "let", kind: .keyword)))
    }

    func testPythonTripleStringState() {
        var state = SyntaxHighlighter.State()
        _ = SyntaxHighlighter.highlight("s = \"\"\"doc", language: .python, state: &state)
        XCTAssertNotNil(state.tripleDelimiter)
        let tokens = SyntaxHighlighter.highlight("more text\"\"\" rest", language: .python, state: &state)
        XCTAssertNil(state.tripleDelimiter)
        XCTAssertTrue(tokens.contains { $0.kind == .string && $0.text.hasPrefix("more text") })
    }

    func testMarkdownHeadingsAndFence() {
        var state = SyntaxHighlighter.State()
        let heading = SyntaxHighlighter.highlight("# Title", language: .markdown, state: &state)
        XCTAssertEqual(heading.first?.kind, .heading)
        _ = SyntaxHighlighter.highlight("```swift", language: .markdown, state: &state)
        XCTAssertTrue(state.inCodeFence)
        let inside = SyntaxHighlighter.highlight("plain code", language: .markdown, state: &state)
        XCTAssertEqual(inside.first?.kind, .plain)
        _ = SyntaxHighlighter.highlight("```", language: .markdown, state: &state)
        XCTAssertFalse(state.inCodeFence)
    }

    func testNumbers() {
        var state = SyntaxHighlighter.State()
        let tokens = SyntaxHighlighter.highlight("let n = 0xFF", language: .rust, state: &state)
        XCTAssertTrue(tokens.contains(HighlightToken(text: "0xFF", kind: .number)))
        XCTAssertTrue(tokens.contains(HighlightToken(text: "let", kind: .keyword)))
    }
}
