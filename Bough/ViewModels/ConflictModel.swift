import Foundation
import Combine

/// Conflict resolution session for the current merge/rebase state.
@MainActor
final class ConflictModel: ObservableObject {
    @Published private(set) var files: [StatusEntry] = []
    @Published var selectedFile: StatusEntry?
    @Published private(set) var parseResult = ConflictParser.ParseResult(segments: [])
    @Published private(set) var isBusy = false
    @Published var notice: String?

    private let repository: GitRepository
    private let accessProvider: RepositoryAccessProvider

    init(repository: GitRepository, accessProvider: RepositoryAccessProvider) {
        self.repository = repository
        self.accessProvider = accessProvider
    }

    var selectedWorktreeURL: URL? {
        guard let file = selectedFile else { return nil }
        return repository.root.appendingPathComponent(file.path)
    }

    /// Call when the sheet opens (or after refresh): reload unmerged files.
    func load(files: [StatusEntry]) async {
        self.files = files
        if selectedFile == nil || !files.contains(where: { $0.id == selectedFile?.id }) {
            await select(files.first)
        }
    }

    func select(_ file: StatusEntry?) async {
        selectedFile = file
        notice = nil
        parseResult = ConflictParser.ParseResult(segments: [])
        guard let file, let url = worktreeURL(for: file) else { return }
        do {
            let data = try accessProvider.dataForFile(at: url)
            parseResult = ConflictParser.parse(String(decoding: data, as: UTF8.self))
        } catch {
            notice = "无法读取文件：\(error.localizedDescription)"
        }
    }

    func setChoice(_ choice: ConflictParser.ConflictBlock.Choice, blockIndex: Int) {
        guard parseResult.segments.indices.contains(blockIndex),
              case .conflict(var block) = parseResult.segments[blockIndex] else { return }
        block.choice = (block.choice == choice) ? nil : choice
        parseResult.segments[blockIndex] = .conflict(block)
    }

    /// Write resolved content back and `git add` the file.
    func saveAndStage() async {
        guard let file = selectedFile, let url = selectedWorktreeURL else { return }
        guard parseResult.allResolved else {
            notice = "还有 \(parseResult.unresolvedCount) 处冲突未选择"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let text = ConflictParser.resolvedText(parseResult)
            try accessProvider.writeData(Data(text.utf8), to: url)
            try await repository.runOrThrow(["add", "--", file.path])
            notice = "已保存并标记解决"
            await select(nil)
            await load(files: files.filter { $0.id != file.id })
        } catch {
            notice = error.localizedDescription
            Log.git.error("conflict save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Mark externally-resolved file (edited outside Bough) as done.
    func markExternallyResolved(_ file: StatusEntry) async {
        do {
            try await repository.runOrThrow(["add", "--", file.path])
            await load(files: files.filter { $0.id != file.id })
        } catch {
            notice = error.localizedDescription
        }
    }

    private func worktreeURL(for entry: StatusEntry) -> URL? {
        // Conflict paths are always inside the worktree root.
        repository.root.appendingPathComponent(entry.path)
    }
}
