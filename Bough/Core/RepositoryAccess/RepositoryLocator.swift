import Foundation

/// Git repository discovery & structural validation (stateless pure functions).
///
/// Internal infrastructure for RepositoryAccessProvider implementations;
/// business code must go through the protocol, never touch disk paths directly.
///
/// Semantics mirror git itself:
/// - "git rev-parse --show-toplevel": walk up from the selected directory to the first
///   directory containing a .git entry.
/// - ".git" can be a directory (normal repo) or a FILE (worktree/submodule),
///   whose content is "gitdir: <path>" (absolute or relative to the worktree root).

enum RepositoryLocator {
    enum LocatorError: LocalizedError, Equatable {
        case pathDoesNotExist(String)
        case notADirectory(String)
        case notAGitRepository(String)
        case malformedGitFile(String)
        case invalidGitDirectory(String)

        var errorDescription: String? {
            switch self {
            case .pathDoesNotExist(let p):
                return "路径不存在：\(p)"
            case .notADirectory(let p):
                return "路径不是文件夹：\(p)"
            case .notAGitRepository(_):
                return "所选目录不是 Git 仓库（未找到 .git）"
            case .malformedGitFile(let p):
                return ".git 文件形态异常：\(p)"
            case .invalidGitDirectory(let p):
                return "git 目录结构不完整：\(p)"
            }
        }
    }

    // MARK: - Entry points

    /// Walk up from `path` to the enclosing worktree root.
    /// Mirrors the directory semantics of "git rev-parse --show-toplevel":
    /// picking a subfolder still resolves to the repo root above it.
    static func locateWorkTreeRoot(at path: String) throws -> URL {
        let fm = FileManager.default
        let expanded = (path as NSString).expandingTildeInPath
        let start = URL(fileURLWithPath: expanded, isDirectory: true)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: start.path, isDirectory: &isDir) else {
            throw LocatorError.pathDoesNotExist(path)
        }
        guard isDir.boolValue else {
            throw LocatorError.notADirectory(path)
        }

        var current = start.standardizedFileURL
        while true {
            if hasGitEntry(at: current) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        throw LocatorError.notAGitRepository(start.path)
    }

    /// Resolve the real gitdir behind a worktree root.
    /// - ".git" directory: validate structure and return it.
    /// - ".git" file (worktree/submodule): parse "gitdir: <path>" and validate the target.
    static func resolveGitDirectory(inWorkTree root: URL) throws -> URL {
        let fm = FileManager.default
        let entry = root.appendingPathComponent(".git", isDirectory: false)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: entry.path, isDirectory: &isDir) else {
            throw LocatorError.notAGitRepository(root.path)
        }

        if isDir.boolValue {
            guard isValidGitDir(entry) else {
                throw LocatorError.invalidGitDirectory(entry.path)
            }
            return entry
        }

        let contents = (try? String(contentsOf: entry, encoding: .utf8)) ?? ""
        guard let target = gitDirReference(in: contents) else {
            throw LocatorError.malformedGitFile(entry.path)
        }

        let resolved = target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : root.appendingPathComponent(target)
        let gitdir = resolved.standardizedFileURL
        guard isValidGitDir(gitdir) else {
            throw LocatorError.invalidGitDirectory(gitdir.path)
        }
        return gitdir
    }

    // MARK: - Primitives

    static func hasGitEntry(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    /// A gitdir is valid when HEAD exists and either (objects + refs) are present
    /// (normal gitdir) or a commondir file exists (linked-worktree gitdir).
    static func isValidGitDir(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.appendingPathComponent("HEAD").path) else { return false }
        let objects = fm.fileExists(atPath: url.appendingPathComponent("objects").path, isDirectory: &isDir) && isDir.boolValue
        let refs = fm.fileExists(atPath: url.appendingPathComponent("refs").path, isDirectory: &isDir) && isDir.boolValue
        let commondir = fm.fileExists(atPath: url.appendingPathComponent("commondir").path)
        return (objects && refs) || commondir
    }

    /// Parse "gitdir: <path>" from .git file content (git's worktree/submodule convention).
    static func gitDirReference(in contents: String) -> String? {
        guard let line = contents.split(separator: "\n").first else { return nil }
        guard line.hasPrefix("gitdir: ") else { return nil }
        let target = line.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? nil : target
    }
}
