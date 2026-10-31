import AppKit
import Combine

/// Right-pane state: selected commit or working-copy file, its changed files,
/// and the currently rendered diff.
@MainActor
final class DetailModel: ObservableObject {
    enum Selection: Equatable {
        case commit(Commit)
        /// staged: diff against HEAD (index side); untracked renders as all-additions.
        case worktreeFile(path: String, staged: Bool, isUntracked: Bool)
        /// Stash patch preview.
        case stash(StashEntry)
    }

    struct RenderedDiff: Equatable {
        let fileChange: FileChange?
        let diff: DiffFile?
        let oldImage: NSImage?
        let newImage: NSImage?
        let truncated: Bool
        /// Raw unified diff text (hunk selection for partial staging).
        var rawDiffText: String = ""
    }

    @Published var selection: Selection?
    @Published private(set) var files: [FileChange] = []
    @Published private(set) var rendered: RenderedDiff?
    @Published var selectedFile: FileChange?
    @Published var showsSideBySide = false
    /// Hunk checkboxes in worktree diff mode (indices into DiffFile.hunks).
    @Published var selectedHunks: Set<Int> = []
    /// Blame mode for the selected file (worktree: HEAD; commit: at that ref).
    @Published var showsBlame = false
    @Published private(set) var blame: BlameResult?
    /// Weak back-reference for status refresh after partial staging.
    weak var parentWorkspace: WorkspaceModel?

    /// Detail header info when a commit is selected.
    @Published private(set) var headerCommit: Commit?
    private let repository: GitRepository
    private let lineCap = 5000

    init(repository: GitRepository) {
        self.repository = repository
    }

    // MARK: - Selection

    func select(_ selection: Selection?) {
        guard selection != self.selection else { return }
        self.selection = selection
        selectedFile = nil
        files = []
        rendered = nil
        headerCommit = nil
        selectedHunks = []
        showsBlame = false
        blame = nil
        Task { await load() }
    }

    private func load() async {
        switch selection {
        case .commit(let commit):
            headerCommit = (try? await repository.commitBody(sha: commit.sha)) ?? commit
            files = (try? await repository.changedFiles(sha: commit.sha)) ?? []
            if files.isEmpty {
                rendered = nil
            } else if selectedFile == nil {
                selectFile(files[0])
            }
        case .worktreeFile(let path, let staged, let isUntracked):
            let kind: FileChange.Kind = isUntracked ? .untracked
                : (staged ? .modified : .modified)
            let change = FileChange(path: path, originalPath: nil, kind: kind, isBinary: false)
            files = [change]
            selectFile(change)
        case .stash(let entry):
            // selectFile routes into renderFile, which renders the stash patch.
            let change = FileChange(path: entry.selector, originalPath: nil,
                                    kind: .modified, isBinary: false)
            files = [change]
            selectFile(change)
        case nil:
            break
        }
        let selectionDescription = String(describing: selection)
        Log.ui.info("detail loaded for \(selectionDescription, privacy: .public)")
    }

    /// Select a file inside the commit (or the single worktree file) and render its diff.
    func selectFile(_ file: FileChange) {
        selectedFile = file
        selectedHunks = []
        Task { await renderFile(file) }
    }

    /// Toggle blame mode; loads/refreshes blame for the current file.
    func setBlame(_ enabled: Bool) async {
        showsBlame = enabled
        guard enabled else { return }
        do {
            switch selection {
            case .worktreeFile(let path, _, let isUntracked):
                guard !isUntracked else { blame = nil; return }
                blame = try await repository.blame(path: path)
            case .commit(let commit):
                guard let file = selectedFile else { blame = nil; return }
                blame = try await repository.blame(path: file.path, ref: commit.sha)
            case nil, .stash:
                blame = nil
            }
        } catch {
            blame = nil
            parentWorkspace?.banner = .error(error.localizedDescription)
        }
    }

    private func renderFile(_ file: FileChange) async {
        switch selection {
        case .commit(let commit):
            guard let diffData = try? await repository.fileDiff(sha: commit.sha, path: file.path) else {
                rendered = RenderedDiff(fileChange: file, diff: nil, oldImage: nil, newImage: nil, truncated: false)
                return
            }
            await render(data: diffData, file: file, commitSha: commit.sha)
        case .worktreeFile(let path, let staged, let isUntracked):
            guard let diffData = try? await repository.worktreeDiff(path: path, staged: staged, isUntracked: isUntracked) else {
                rendered = RenderedDiff(fileChange: file, diff: nil, oldImage: nil, newImage: nil, truncated: false)
                return
            }
            await render(data: diffData, file: file, commitSha: nil)
        case .stash(let entry):
            guard let diffData = try? await repository.stashShow(entry.selector) else {
                rendered = nil
                return
            }
            let stashFile = FileChange(path: entry.message,
                                       originalPath: nil,
                                       kind: .modified,
                                       isBinary: false)
            await render(data: diffData, file: stashFile, commitSha: nil)
        case nil:
            break
        }
    }

    private func render(data: Data, file: FileChange, commitSha: String?) async {
        let text = String(decoding: data, as: UTF8.self)
        var parsed = DiffParser.parse(text).first
        var truncated = false
        // Cap rendered lines for pathological diffs.
        if var file = parsed, file.hunks.count > 0 {
            var kept: [DiffHunk] = []
            var budget = lineCap
            for var hunk in file.hunks {
                guard budget > 0 else { truncated = true; break }
                if hunk.lines.count > budget {
                    hunk = DiffHunk(oldStart: hunk.oldStart, oldCount: hunk.oldCount,
                                    newStart: hunk.newStart, newCount: hunk.newCount,
                                    section: hunk.section,
                                    lines: Array(hunk.lines.prefix(budget)))
                    truncated = true
                }
                budget -= hunk.lines.count
                kept.append(hunk)
                if truncated { break }
            }
            parsed = DiffFile(hunks: kept, isBinary: file.isBinary, path: file.path)
        }
        // Image preview: binary + known extension -> load both versions.
        if let parsed, parsed.isBinary, file.isImage, let sha = commitSha {
            let oldData = try? await repository.blobContent(ref: "\(sha)^", path: file.path)
            let newData = try? await repository.blobContent(ref: sha, path: path(for: file))
            rendered = RenderedDiff(fileChange: file,
                                    diff: parsed,
                                    oldImage: oldData.flatMap { NSImage(data: $0) },
                                    newImage: newData.flatMap { NSImage(data: $0) },
                                    truncated: truncated,
                                    rawDiffText: text)
            return
        }
        rendered = RenderedDiff(fileChange: file, diff: parsed,
                                oldImage: nil, newImage: nil, truncated: truncated,
                                rawDiffText: text)
    }

    /// Partial staging from hunk checkboxes (worktree mode only):
    /// stage = apply unstaged diff hunks to index; unstage = reverse-apply.
    func applySelectedHunks(stage: Bool) async {
        guard case .worktreeFile(let path, let staged, _) = selection,
              let rendered, !selectedHunks.isEmpty else { return }
        guard stage != staged else { return } // direction must match current side
        guard let patch = DiffParser.patch(fromDiff: rendered.rawDiffText,
                                           selecting: Array(selectedHunks)) else { return }
        do {
            try await repository.applyPatch(Data(patch.utf8), reverse: !stage)
            selectedHunks = []
            await parentWorkspace?.refresh()
            await load()
        } catch {
            parentWorkspace?.banner = .error(error.localizedDescription)
            Log.git.error("hunk apply failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Rename-aware blob path: the versioned name at that ref.
    private func path(for file: FileChange) -> String {
        file.path
    }
}
