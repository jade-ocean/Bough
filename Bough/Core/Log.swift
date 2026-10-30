import os

/// Unified logging egress. Filter in Console.app by subsystem.
enum Log {
    private static let subsystem = "com.wangyuyang.bough"

    /// App lifecycle, menu routing.
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Repository open/validate flow.
    static let repository = Logger(subsystem: subsystem, category: "repository")
    /// Git engine invocations.
    static let git = Logger(subsystem: subsystem, category: "git")
    /// UI state transitions.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
