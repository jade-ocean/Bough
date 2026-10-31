import Foundation

/// Per-repository lazy file-tree cache, shared across FileTreeSheet
/// presentations. Keyed by ref string; cleared on any repository mutation
/// (symbolic refs like HEAD go stale after commits).
@MainActor
final class FileTreeCache {
    private var roots: [String: GitRepository.TreeNode] = [:]
    /// Per-ref loaded folders: path -> loaded subtree node.
    private var children: [String: [String: GitRepository.TreeNode]] = [:]

    func cachedRoot(ref: String) -> GitRepository.TreeNode? {
        roots[ref]
    }

    func storeRoot(ref: String, _ node: GitRepository.TreeNode) {
        roots[ref] = node
    }

    /// Previously loaded folder for ref+prefix (nil = not cached).
    func cachedChildren(ref: String, prefix: String) -> GitRepository.TreeNode? {
        children[ref]?[prefix]
    }

    func storeChildren(ref: String, prefix: String, _ loaded: GitRepository.TreeNode) {
        children[ref, default: [:]][prefix] = loaded
    }

    /// Drop everything (called after mutations; trees are cheap to reload).
    func clear() {
        roots = [:]
        children = [:]
    }

    var isEmpty: Bool { roots.isEmpty && children.isEmpty }
}
