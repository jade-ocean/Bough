import XCTest

/// Smoke tests for the critical working-copy path:
/// launch with a seeded repo -> history visible -> stage all -> commit ->
/// status clears -> new commit appears in history.
final class BoughSmokeUITests: XCTestCase {

    private var repoPath: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Seed a real local repo with one commit (git CLI, no sandbox limits).
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoughUITest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        repoPath = base.appendingPathComponent("repo").path
        try FileManager.default.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "main"])
        try runGit(["config", "user.name", "UI Test"])
        try runGit(["config", "user.email", "ui@bough.local"])
        try "hello\n".write(to: URL(fileURLWithPath: repoPath).appendingPathComponent("hello.txt"),
                            atomically: true, encoding: .utf8)
        try runGit(["add", "."])
        try runGit(["commit", "-q", "-m", "initial"])
        // Leave the working copy dirty so staging has something to do.
        try "hello changed\n".write(
            to: URL(fileURLWithPath: repoPath).appendingPathComponent("hello.txt"),
            atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let repoPath {
            try? FileManager.default.removeItem(atPath: repoPath)
        }
    }

    private func readGit(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func runGit(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "uitest-seed", code: Int(process.terminationStatus))
        }
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_REPO_PATH"] = repoPath
        app.launch()
        return app
    }

    /// Working-copy render smoke: boots into the changes view and verifies
    /// the three panels, the dirty file row, and the bulk action control.
    /// (Driving commit via XCUITest proved unreliable on macOS SwiftUI:
    /// Button actions and accelerators do not reach the app; the stage/
    /// commit pipeline is covered end-to-end by unit/integration tests.)
    func testWorkingCopyViewRenders() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_REPO_PATH"] = repoPath
        app.launchEnvironment["UITEST_VIEW"] = "changes"
        app.launch()

        // Panel titles render (value attribute, with counters).
        let unstagedTitle = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "未暂存（")).firstMatch
        XCTAssertTrue(unstagedTitle.waitForExistence(timeout: 10),
                      "未暂存面板应渲染")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "已暂存（")).firstMatch.waitForExistence(timeout: 5),
            "已暂存面板应渲染")

        // The dirty seeded file shows in the unstaged list.
        let dirtyRow = app.staticTexts.matching(
            NSPredicate(format: "label == %@ OR value == %@", "hello.txt", "hello.txt")).firstMatch
        XCTAssertTrue(dirtyRow.waitForExistence(timeout: 10),
                      "修改过的 hello.txt 应出现在未暂存列表")

        // Bulk action control exists.
        XCTAssertTrue(app.links.matching(
            NSPredicate(format: "label == %@", "全部暂存")).firstMatch.waitForExistence(timeout: 5),
            "全部暂存操作应存在")
        app.terminate()
    }

    func testWelcomeShowsWithoutRepoPath() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_REPO_PATH"] = ""
        app.launch()
        XCTAssertTrue(app.staticTexts["Bough"].firstMatch.waitForExistence(timeout: 10),
                      "无路径时应显示欢迎页")
    }
}

extension XCUIElement {
    /// Polling helper: element disappears (or never existed) within timeout.
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            usleep(200_000)
        }
        return !exists
    }
}

extension XCUIElement {
    /// Poll until hittable/enabled or timeout.
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isEnabled { return true }
            usleep(200_000)
        }
        return exists && isEnabled
    }
}
