import Foundation

/// Cross-window "open in new window" handoff.
/// Set pending before openWindow(id:); the new window consumes it on first task.
@MainActor
final class PendingOpenRouter: ObservableObject {
    static let shared = PendingOpenRouter()

    @Published var pendingPath: String?

    private init() {}

    func take() -> String? {
        defer { pendingPath = nil }
        return pendingPath
    }
}
