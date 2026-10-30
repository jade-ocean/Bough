import Foundation

/// A single git invocation (arguments are repo-relative and option-injection-safe
/// because pathspecs are always passed after "--").
struct GitCommand: Sendable {
    var arguments: [String]
    var timeout: TimeInterval
    var stdinData: Data?
    var extraEnvironment: [String: String]

    init(_ arguments: [String],
         timeout: TimeInterval = 30,
         stdinData: Data? = nil,
         extraEnvironment: [String: String] = [:]) {
        self.arguments = arguments
        self.timeout = timeout
        self.stdinData = stdinData
        self.extraEnvironment = extraEnvironment
    }
}

/// Captured outcome of a git invocation.
struct GitResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: Data
    var stderr: String
    var duration: TimeInterval

    var succeeded: Bool { exitCode == 0 }
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
}
