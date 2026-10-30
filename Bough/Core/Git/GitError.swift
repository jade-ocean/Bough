import Foundation

/// Errors surfaced by the git engine layer.
enum GitError: LocalizedError, Equatable {
    /// git binary not found on this machine.
    case binaryNotFound
    /// Command exceeded its timeout and was killed.
    case timedOut(command: String)
    /// Command was cancelled (Task cancellation or timeout kill).
    case cancelled(command: String)
    /// git exited non-zero; carries the joined command line and stderr.
    case executionFailed(command: String, exitCode: Int32, stderr: String)
    /// Command succeeded structurally but output could not be parsed.
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "未找到可用的 git 可执行文件，请确认已安装 Xcode Command Line Tools"
        case .timedOut(let command):
            return "git 命令超时被终止：\(command)"
        case .cancelled(let command):
            return "git 命令已取消：\(command)"
        case .executionFailed(let command, let exitCode, let stderr):
            let tail = stderr.split(separator: "\n").suffix(2).joined(separator: " ")
            return "git 命令失败（\(exitCode)）：\(command)\(tail.isEmpty ? "" : " — \(tail)")"
        case .unexpectedOutput(let detail):
            return "无法解析 git 输出：\(detail)"
        }
    }
}
