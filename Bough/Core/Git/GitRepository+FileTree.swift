import Foundation

/// Snapshot file tree of any commit (Phase: file tree browsing).
extension GitRepository {

    struct TreeNode: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case file
            case folder
        }

        let kind: Kind
        /// Path relative to repository root ("" for the virtual root).
        let path: String
        let name: String
        /// nil = not loaded yet (lazy mode); [] = loaded, empty folder.
        var children: [TreeNode]?
        /// Blob size in bytes (files only, from ls-tree -l; nil on parse gap).
        let size: Int?
        /// Folders: true once `children` reflects the on-disk tree.
        var childrenLoaded: Bool = false

        var id: String { path }
        var isFile: Bool { kind == .file }
    }

    struct TreeItem: Equatable, Sendable {
        let mode: String
        let type: String
        let sha: String
        let size: Int?
        let path: String
    }

    /// `git ls-tree -r -l <ref>` -> flat items (validated output kept for tests).
    func listTree(ref: String) async throws -> [TreeItem] {
        let result = try await runOrThrow(["ls-tree", "-r", "-l", ref], serial: false)
        return GitTreeParser.parseFlat(result.stdoutText)
    }

    /// Build the full nested snapshot tree for a ref (eager; small repos/tests).
    func fileTree(ref: String) async throws -> TreeNode {
        let items = try await listTree(ref: ref)
        return GitTreeParser.buildTree(items)
    }

    /// One directory level, non-recursive: `git ls-tree -l <ref> -- <prefix>/`.
    /// Folder rows come back with children == nil (lazy, load on expand).
    func treeDir(ref: String, prefix: String) async throws -> TreeNode {
        var args = ["ls-tree", "-l", ref]
        args += prefix.isEmpty ? ["--", "."] : ["--", prefix + "/"]
        let result = try await runOrThrow(args, serial: false)
        let items = GitTreeParser.parseFlat(result.stdoutText)
        var children: [TreeNode] = items.map { item in
            let name = item.path.split(separator: "/").last.map(String.init) ?? item.path
            if item.type == "tree" {
                return TreeNode(kind: .folder, path: item.path, name: name,
                                children: nil, size: nil, childrenLoaded: false)
            }
            return TreeNode(kind: .file, path: item.path, name: name,
                            children: nil, size: item.size, childrenLoaded: true)
        }
        children.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .folder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return TreeNode(kind: .folder, path: prefix, name: prefix.isEmpty ? "/" : prefix,
                        children: children, size: nil, childrenLoaded: true)
    }


}

enum GitTreeParser {

    /// "100644 blob a1b2c3\t1234\tpath/to/file.txt" (-r -l layout).
    static func parseFlat(_ output: String) -> [GitRepository.TreeItem] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let meta = parts[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard meta.count >= 3 else { return nil }
            let size = meta.count > 3 ? Int(meta[3]) : nil
            return GitRepository.TreeItem(mode: meta[0], type: meta[1], sha: meta[2],
                                          size: size, path: String(parts[1]))
        }
    }

    /// Fold flat paths into nested folders/files, folders first, sorted.
    static func buildTree(_ items: [GitRepository.TreeNode]) -> GitRepository.TreeNode {
        buildTree(items.map { GitRepository.TreeItem(mode: "100644", type: "blob", sha: "a", size: $0.size, path: $0.path) })
    }

    /// Fold flat paths into nested folders/files (TreeNode is a value type:
    /// recursion via inout so mutation propagates to the root).
    static func buildTree(_ items: [GitRepository.TreeItem]) -> GitRepository.TreeNode {
        var root = GitRepository.TreeNode(kind: .folder, path: "", name: "/",
                                          children: [], size: nil, childrenLoaded: true)
        for item in items {
            insert(into: &root, segments: item.path.split(separator: "/").map(String.init),
                   item: item)
        }
        sortNode(&root)
        return root
    }

    private static func insert(into node: inout GitRepository.TreeNode,
                               segments: [String], item: GitRepository.TreeItem) {
        guard !segments.isEmpty else { return }
        let segment = segments[0]
        if segments.count == 1 {
            node.children?.append(GitRepository.TreeNode(
                kind: .file, path: item.path, name: segment, children: nil,
                size: item.size, childrenLoaded: true))
            return
        }
        let folderPath = node.path.isEmpty ? segment : node.path + "/" + segment
        if let index = node.children?.firstIndex(where: {
            $0.path == folderPath && $0.kind == .folder
        }) {
            insert(into: &node.children![index], segments: Array(segments.dropFirst()), item: item)
        } else {
            node.children?.append(GitRepository.TreeNode(
                kind: .folder, path: folderPath, name: segment, children: [],
                size: nil, childrenLoaded: true))
            insert(into: &node.children![node.children!.count - 1],
                   segments: Array(segments.dropFirst()), item: item)
        }
    }

    private static func sortNode(_ node: inout GitRepository.TreeNode) {
        guard var children = node.children else { return }
        children.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .folder } // folders first
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for index in children.indices {
            sortNode(&children[index])
        }
        node.children = children
    }

    /// Replace a folder's children in a tree (path-addressed, value semantics).
    static func updateChildren(of path: String, in root: GitRepository.TreeNode,
                               with loaded: GitRepository.TreeNode) -> GitRepository.TreeNode {
        var root = root
        applyChildren(&root, target: path, loaded: loaded)
        return root
    }

    private static func applyChildren(_ node: inout GitRepository.TreeNode, target: String,
                                      loaded: GitRepository.TreeNode) {
        guard node.kind == .folder else { return }
        if node.path == target {
            node.children = loaded.children
            node.childrenLoaded = true
            return
        }
        if var children = node.children {
            for index in children.indices where children[index].kind == .folder {
                applyChildren(&children[index], target: target, loaded: loaded)
            }
            node.children = children
        }
    }
}
