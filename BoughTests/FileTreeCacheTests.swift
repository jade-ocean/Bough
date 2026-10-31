import XCTest
@testable import Bough

@MainActor
final class FileTreeCacheTests: XCTestCase {

    private func folder(_ path: String, names: [String], loaded: Bool) -> GitRepository.TreeNode {
        GitRepository.TreeNode(
            kind: .folder, path: path, name: path.split(separator: "/").last.map(String.init) ?? path,
            children: names.map {
                GitRepository.TreeNode(kind: .file, path: path.isEmpty ? $0 : "\(path)/\($0)",
                                       name: $0, children: nil, size: 1, childrenLoaded: true)
            }, size: nil, childrenLoaded: loaded)
    }

    func testRootRoundTripAndClear() {
        let cache = FileTreeCache()
        XCTAssertTrue(cache.isEmpty)
        let root = folder("", names: ["a.txt"], loaded: true)
        cache.storeRoot(ref: "HEAD", root)
        XCTAssertEqual(cache.cachedRoot(ref: "HEAD"), root)
        XCTAssertFalse(cache.isEmpty)
        cache.clear()
        XCTAssertNil(cache.cachedRoot(ref: "HEAD"))
        XCTAssertTrue(cache.isEmpty)
    }

    func testChildrenPerRefAndPrefix() {
        let cache = FileTreeCache()
        let src = folder("src", names: ["a.swift"], loaded: true)
        cache.storeChildren(ref: "abc", prefix: "src", src)
        XCTAssertEqual(cache.cachedChildren(ref: "abc", prefix: "src"), src)
        XCTAssertNil(cache.cachedChildren(ref: "abc", prefix: "lib")) // other prefix
        XCTAssertNil(cache.cachedChildren(ref: "def", prefix: "src")) // other ref
    }

    func testUpdateChildrenSplicesCachedSubtree() {
        // Root contains the lazy placeholder for src (top-level listing).
        var root = folder("", names: ["a.txt"], loaded: true)
        root.children?.append(GitRepository.TreeNode(
            kind: .folder, path: "src", name: "src", children: nil,
            size: nil, childrenLoaded: false))
        let srcLoaded = folder("src", names: ["deep.swift"], loaded: true)
        let updated = GitTreeParser.updateChildren(of: "src", in: root, with: srcLoaded)
        let spliced = updated.children?.first { $0.name == "src" }
        XCTAssertEqual(spliced?.childrenLoaded, true)
        XCTAssertEqual(spliced?.children?.first?.name, "deep.swift")
    }
}
