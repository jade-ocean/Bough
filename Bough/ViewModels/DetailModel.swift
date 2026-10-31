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
    /// File to auto-select once a commit's changed-files list loads.
    private var pendingFilePath: String?
    /// Monotonic token: every select/selectFile bumps it; async loads may only
    /// publish results of the LATEST generation (fast consecutive clicks
    /// otherwise let stale tasks overwrite newer selections).
    private var generation = 0
    @Published private(set) var isLoadingDetail = false

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
        generation += 1
        self.selection = selection
        selectedFile = nil
        files = []
        rendered = nil
        headerCommit = nil
        selectedHunks = []
        showsBlame = false
        blame = nil
        Task { await load(generation: generation) }
    }

    private func load(generation gen: Int) async {
        isLoadingDetail = true
        defer { if gen == self.generation { isLoadingDetail = false } }
        switch selection {
        case .commit(let commit):
            Log.git.info("detail load enter gen=\(gen) sha=\(commit.sha.prefix(7), privacy: .public)")
            async let headerFetch = repository.commitBody(sha: commit.sha)
            async let filesFetch = repository.changedFiles(sha: commit.sha)
            let header = try? await headerFetch
            let loadedFiles = (try? await filesFetch) ?? []
            Log.git.info("detail load fetched gen=\(gen) latest=\(gen == self.generation) files=\(loadedFiles.count)")
            guard gen == generation else { return }
            headerCommit = header ?? commit
            files = loadedFiles
            Log.git.info("detail load published gen=\(gen)")
            let preferred = pendingFilePath.flatMap { path in
                files.first { $0.path == path }
            }
            pendingFilePath = nil
            if let preferred {
                selectFile(preferred)
            } else if files.isEmpty {
                if gen == generation { rendered = nil }
            } else if selectedFile == nil {
                selectFile(files[0])
            }
        case .worktreeFile(let path, let staged, let isUntracked):
            let kind: FileChange.Kind = isUntracked ? .untracked
                : (staged ? .modified : .modified)
            let change = FileChange(path: path, originalPath: nil, kind: kind, isBinary: false)
            guard gen == generation else { return }
            files = [change]
            selectFile(change)
        case .stash(let entry):
            let change = FileChange(path: entry.selector, originalPath: nil,
                                    kind: .modified, isBinary: false)
            guard gen == generation else { return }
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
        // Same file already rendered -> nothing to do (avoids re-parse churn).
        if selectedFile == file, rendered?.fileChange == file { return }
        generation += 1
        selectedFile = file
        selectedHunks = []
        rendered = nil // clear stale diff immediately (real loading feedback)
        Task { await renderFile(file, generation: generation) }
    }

    /// Select a commit, optionally pre-picking one of its changed files.
    func select(commit: Commit, filePath: String?) {
        pendingFilePath = filePath
        select(.commit(commit))
    }
    // (pendingFilePath survives the generation bump by design: it is read
    // inside load of the new generation.)

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

    private func renderFile(_ file: FileChange, generation gen: Int) async {
        defer {
            if gen == generation { isLoadingDetail = false }
            Log.git.info("detail render done gen=\(gen) latest=\(gen == self.generation)")
        }
        switch selection {
        case .commit(let commit):
            let diffData = try? await repository.fileDiff(sha: commit.sha, path: file.path)
            guard gen == generation else { return }
            guard let diffData else {
                rendered = RenderedDiff(fileChange: file, diff: nil, oldImage: nil, newImage: nil, truncated: false)
                return
            }
            await render(data: diffData, file: file, commitSha: commit.sha, generation: gen)
        case .worktreeFile(let path, let staged, let isUntracked):
            let diffData = try? await repository.worktreeDiff(path: path, staged: staged, isUntracked: isUntracked)
            guard gen == generation else { return }
            guard let diffData else {
                rendered = RenderedDiff(fileChange: file, diff: nil, oldImage: nil, newImage: nil, truncated: false)
                return
            }
            await render(data: diffData, file: file, commitSha: nil, generation: gen)
        case .stash(let entry):
            let diffData = try? await repository.stashShow(entry.selector)
            guard gen == generation else { return }
            guard let diffData else {
                rendered = nil
                return
            }
            let stashFile = FileChange(path: entry.message,
                                       originalPath: nil,
                                       kind: .modified,
                                       isBinary: false)
            await render(data: diffData, file: stashFile, commitSha: nil, generation: gen)
        case nil:
            break
        }
    }

    private func render(data: Data, file: FileChange, commitSha: String?, generation gen: Int) async {
        let text = String(decoding: data, as: UTF8.self)
        // Parsing + line-cap run OFF the main actor: large diffs froze the UI here.
        let (parsed, truncated) = await Task.detached(priority: .userInitiated) {
            var parsed = DiffParser.parse(text).first
            var truncated = false
            if var file = parsed, !file.hunks.isEmpty {
                var kept: [DiffHunk] = []
                var budget = 5000
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
            return (parsed, truncated)
        }.value
        guard gen == generation else { return }
        // Image preview: binary + known extension -> load both versions.
        if let parsed, parsed.isBinary, file.isImage, let sha = commitSha {
            let oldData = try? await repository.blobContent(ref: "\(sha)^", path: file.path)
            let newData = try? await repository.blobContent(ref: sha, path: path(for: file))
            guard gen == generation else { return }
            rendered = RenderedDiff(fileChange: file,
                                    diff: parsed,
                                    oldImage: oldData.flatMap { NSImage(data: $0) },
                                    newImage: newData.flatMap { NSImage(data: $0) },
                                    truncated: truncated,
                                    rawDiffText: text)
            return
        }
        guard gen == generation else { return }
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
            generation += 1
            await parentWorkspace?.refresh()
            await load(generation: generation)
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
