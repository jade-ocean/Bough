import Foundation

/// Remote repository cloning (P0 repo management).
enum CloneService {

    /// Git URL shape check. Rules:
    /// - non-empty, never starts with "-" (positional-arg option injection)
    /// - https://, ssh://, git@host:path, file:// or absolute local path
    /// Note: private/enterprise hosts (self-hosted GitLab etc.) are a supported
    /// product scenario, so no host allow/deny filtering happens here.
    static func isValidSource(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.hasPrefix("-") else { return false }
        if t.hasPrefix("https://") || t.hasPrefix("ssh://")
            || t.hasPrefix("git@") || t.hasPrefix("file://") {
            return true
        }
        return t.hasPrefix("/")
    }

    /// Derive a folder name from the URL: last path segment without ".git".
    static func suggestedFolderName(for raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = t.split(separator: ":").last.map(String.init) ?? t
        let name = tail.split(separator: "/").last.map(String.init) ?? "repository"
        let trimmed = name.hasSuffix(".git") ? String(name.dropLast(4)) : name
        let cleaned = trimmed.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "repository" : cleaned
    }

    /// `git clone <url> <dest>` executed inside `parent`; long timeout (network).
    static func clone(url rawURL: String,
                      folderName: String,
                      into parent: URL,
                      gitBinary: String? = nil) async throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSource(trimmed) else {
            throw GitError.executionFailed(command: "clone", exitCode: -1,
                                           stderr: "不支持的仓库地址格式")
        }
        let name = folderName.trimmingCharacters(in: .whitespaces).isEmpty
            ? suggestedFolderName(for: trimmed)
            : folderName.trimmingCharacters(in: .whitespaces)
        let dest = parent.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest.path) else {
            throw GitError.executionFailed(command: "clone", exitCode: -1,
                                           stderr: "目标文件夹已存在：\(dest.path)")
        }
        let binary = try gitBinary ?? GitLocator.locate()
        let executor = GitCommandExecutor(gitBinary: binary, workingDirectory: parent)
        let result = try await executor.run(GitCommand(["clone", trimmed, dest.path],
                                                       timeout: 900))
        guard result.succeeded else {
            // Clean up the likely-empty directory git left behind on failure.
            try? fm.removeItem(at: dest)
            throw GitError.executionFailed(command: "clone \(trimmed)",
                                           exitCode: result.exitCode,
                                           stderr: result.stderr)
        }
        return dest
    }
}
