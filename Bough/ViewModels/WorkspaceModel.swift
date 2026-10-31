import Foundation
import Combine

/// Drives the working-copy (changes + commit) UI for one open repository.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var status = GitStatus()
    @Published private(set) var identity: GitIdentity?
    @Published private(set) var lastCommit: Commit?
    @Published private(set) var isBusy = false
    @Published var banner: MainWindowModel.Banner?

    // Commit composer state
    @Published var commitMessage = ""
    @Published var isAmendEnabled = false
    @Published var signing: CommitSigning = AppPreferences.defaultSigning

    /// Pending discard request awaiting user confirmation (drives the sheet).
    @Published var pendingDiscard: [StatusEntry] = []
    /// Branch checkout paused for the dirty-tree confirmation dialog.
    @Published var pendingCheckout: Branch?

    let repository: GitRepository
    let history: HistoryModel
    let detail: DetailModel
    let branches: BranchModel
    let stash: StashModel
    let tags: TagModel
    let conflict: ConflictModel
    let search: SearchModel

    /// Center column mode: history graph or working copy.
    enum CenterMode: String {
        case history
        case changes
    }

    @Published var centerMode: CenterMode = .history

    init(repository: GitRepository,
         accessProvider: RepositoryAccessProvider = DirectPathAccessProvider()) {
        self.repository = repository
        self.history = HistoryModel(repository: repository)
        self.detail = DetailModel(repository: repository)
        self.branches = BranchModel(repository: repository)
        self.stash = StashModel(repository: repository)
        self.tags = TagModel(repository: repository)
        self.conflict = ConflictModel(repository: repository, accessProvider: accessProvider)
        self.search = SearchModel(repository: repository)
        detail.parentWorkspace = self
        #if DEBUG
        // XCUITest hook: boot straight into the working-copy view.
        if ProcessInfo.processInfo.environment["UITEST_VIEW"] == "changes" {
            centerMode = .changes
        }
        #endif
    }

    var canCommit: Bool {
        guard !status.staged.isEmpty else { return false }
        guard identity?.isComplete == true else { return false }
        return !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAmendEnabled
    }

    var identityHint: String? {
        if let identity, identity.isComplete { return nil }
        return "未配置 git 身份（user.name / user.email），无法提交"
    }
    /// Full refresh for the menu Cmd+R: everything the workspace displays.
    /// Sub-model reloads run concurrently (reads are lock-free and parallel).
    func refreshAll() async {
        async let statusReload: Void = refresh()
        async let branchesReload: Void = branches.reload()
        async let stashReload: Void = stash.reload()
        async let tagsReload: Void = tags.reload()
        async let historyReload: Void = history.reload()
        _ = await (statusReload, branchesReload, stashReload, tagsReload, historyReload)
    }

    // MARK: - Load

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            async let statusFetch = repository.status()
            async let identityFetch = repository.identity()
            (status, identity) = try await (statusFetch, identityFetch)
        } catch {
            banner = .error(error.localizedDescription)
            Log.git.error("status failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Mutations

    func stage(_ entries: [StatusEntry]) async {
        await mutate { try await $0.stage(entries.map(\.path)) }
    }

    func stageAll() async {
        await mutate { try await $0.stageAll() }
    }

    func unstage(_ entries: [StatusEntry]) async {
        await mutate { try await $0.unstage(entries.map(\.path)) }
    }

    func unstageAll() async {
        await mutate { repo in
            let staged = try await repo.status().staged
            try await repo.unstage(staged.map(\.path))
        }
    }

    /// Called after the user confirms the discard sheet.
    func performDiscard(_ entries: [StatusEntry]) async {
        let tracked = entries.filter { !$0.isUntracked }.map(\.path)
        let untracked = entries.filter { $0.isUntracked }.map(\.path)
        await mutate { repo in
            if !tracked.isEmpty { try await repo.discard(tracked) }
            if !untracked.isEmpty { try await repo.discardUntracked(untracked) }
        }
    }

    func commit() async {
        guard canCommit else { return }
        await mutate { repo in
            _ = try await repo.commit(
                message: commitMessage,
                amend: isAmendEnabled,
                signing: signing)
            commitMessage = ""
            isAmendEnabled = false
        }
    }

    /// Toggle amend on: prefill the editor from HEAD's message when empty.
    func setAmend(_ enabled: Bool) async {
        isAmendEnabled = enabled
        guard enabled, commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if lastCommit == nil { lastCommit = try? await repository.lastCommit() }
        guard let last = lastCommit else { return }
        var text = last.subject
        if !last.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n\n" + last.body
        }
        commitMessage = text
    }

    // MARK: - HEAD operations (history context menu)

    /// These touch HEAD/refs, so history reloads after them.
    func checkout(_ commit: Commit) async {
        await mutate(reloadsHistory: true) { try await $0.checkoutCommit(sha: commit.sha) }
    }

    func revert(_ commit: Commit) async {
        await mutate(reloadsHistory: true) { try await $0.revert(sha: commit.sha) }
    }

    func cherryPick(_ commit: Commit) async {
        await mutate(reloadsHistory: true) { try await $0.cherryPick(sha: commit.sha) }
    }

    func reset(to commit: Commit, mode: GitRepository.ResetMode) async {
        await mutate(reloadsHistory: true) { try await $0.reset(sha: commit.sha, mode: mode) }
    }

    // MARK: - Branch & sync operations (Phase 4)

    func createBranch(_ name: String, from startPoint: String?, checkout: Bool) async {
        guard await repository.isBranchNameValid(name) else {
            banner = .error("分支名不合法：\(name)")
            return
        }
        await mutate { try await $0.createBranch(name, startPoint: startPoint, checkout: checkout) }
    }

    func delete(_ branch: Branch, force: Bool) async {
        await mutate { try await $0.deleteBranch(branch.name, force: force) }
    }

    func rename(_ branch: Branch, to newName: String) async {
        guard await repository.isBranchNameValid(newName) else {
            banner = .error("分支名不合法：\(newName)")
            return
        }
        await mutate { try await $0.renameBranch(branch.name, to: newName) }
    }

    func checkout(_ branch: Branch) async {
        await mutate(reloadsHistory: true) { try await $0.checkoutBranch(branch.name) }
    }

    /// Dirty tree -> ask via confirmation dialog; clean -> switch directly.
    func requestCheckout(_ branch: Branch) async {
        if status.hasChanges {
            pendingCheckout = branch
        } else {
            await checkout(branch)
        }
    }

    /// Dialog action: auto-stash, switch, restore; retained stash reported.
    func checkoutWithStash(_ branch: Branch) async {
        pendingCheckout = nil
        var outcome: GitRepository.CheckoutOutcome?
        await mutate(reloadsHistory: true) {
            outcome = try await $0.checkoutBranchPreservingChanges(
                branch.name, autoStashMessage: "Bough: 检出 \(branch.name) 前自动暂存")
        }
        if outcome == .switchedWithRetainedStash {
            banner = .info("已检出「\(branch.name)」；更改已尽量恢复，stash@{0} 保留待确认（有冲突时用侧栏 Stash 处理）")
        }
    }

    /// DWIM checkout of a remote branch: git creates a local tracking branch
    /// automatically when the name is unambiguous.
    func checkoutRemote(named shortName: String) async {
        await mutate(reloadsHistory: true) { try await $0.checkoutBranch(shortName) }
    }

    /// Merge another branch into the current one.
    func merge(_ branch: Branch) async {
        await mutate(reloadsHistory: true) { try await $0.merge(branch.name) }
    }

    /// Rebase the current branch onto another branch.
    func rebase(onto branch: Branch) async {
        await mutate(reloadsHistory: true) { try await $0.rebase(onto: branch.name) }
    }

    func abortRebase() async {
        await mutate(reloadsHistory: true) { try await $0.rebaseAbort() }
    }

    func continueRebase() async {
        await mutate(reloadsHistory: true) { try await $0.rebaseContinue() }
    }

    func abortMerge() async {
        await mutate(reloadsHistory: true) { try await $0.runOrThrow(["merge", "--abort"]) }
    }

    func fetchAll() async {
        await mutate { try await $0.fetch() }
    }

    func pull(strategy: GitRepository.PullStrategy) async {
        await mutate(reloadsHistory: true) { try await $0.pull(strategy: strategy) }
    }

    func push(forceWithLease: Bool = false) async {
        await mutate { try await $0.push(forceWithLease: forceWithLease) }
    }

    func addRemote(name: String, url: String) async {
        await mutate { try await $0.addRemote(name: name, url: url) }
    }

    func removeRemote(_ remote: RemoteInfo) async {
        await mutate { try await $0.removeRemote(name: remote.name) }
    }

    // MARK: - Blame -> history navigation

    /// Jump from a blame line to its authoring commit: switch to history
    /// mode and select the commit (right pane shows its detail). The history
    /// list highlights the row when visible; scrolling-to is not attempted.
    func openCommit(sha: String) async {
        do {
            guard let commit = try await repository.commitBody(sha: sha) else {
                banner = .error("未找到提交：\(sha.prefix(7))")
                return
            }
            centerMode = .history
            detail.select(.commit(commit))
        } catch {
            banner = .error(error.localizedDescription)
        }
    }

    // MARK: - Reflog recovery (working-copy pack)

    func checkoutDetached(_ entry: ReflogEntry) async {
        await mutate(reloadsHistory: true) { try await $0.checkoutCommit(sha: entry.sha) }
    }

    func branchFromReflog(_ entry: ReflogEntry, name: String) async {
        guard await repository.isBranchNameValid(name) else {
            banner = .error("分支名不合法：\(name)")
            return
        }
        await mutate { try await $0.createBranch(at: entry.sha, name: name) }
    }

    func resetTo(sha: String, mode: GitRepository.ResetMode) async {
        await mutate(reloadsHistory: true) { try await $0.reset(sha: sha, mode: mode) }
    }

    // MARK: - Stash (Phase 5)

    func stashCreate(message: String, includeUntracked: Bool) async {
        await mutate { try await $0.stashPush(message: message, includeUntracked: includeUntracked) }
    }

    func stashApply(_ entry: StashEntry) async {
        await mutate { try await $0.stashApply(entry.selector) }
    }

    func stashPop(_ entry: StashEntry) async {
        await mutate { try await $0.stashPop(entry.selector) }
    }

    func stashDrop(_ entry: StashEntry) async {
        await mutate { try await $0.stashDrop(entry.selector) }
    }

    // MARK: - Tags (Phase 5)

    func createTag(_ name: String, message: String, target: String?, annotated: Bool) async {
        await mutate {
            if annotated {
                try await $0.createAnnotatedTag(name, message: message, target: target)
            } else {
                try await $0.createTag(name, target: target)
            }
        }
    }

    func deleteTag(_ tag: TagEntry) async {
        await mutate { try await $0.deleteTag(tag.name) }
    }

    func pushTag(_ tag: TagEntry) async {
        await mutate { try await $0.pushTag(tag.name) }
    }

    // MARK: - Interactive rebase (Phase 5, simplified)

    func interactiveRebase(base: Commit, steps: [GitRepository.RebaseStep]) async {
        await mutate(reloadsHistory: true) {
            try await $0.rebaseInteractive(base: base.sha, steps: steps)
        }
    }

    /// Mark a conflict-resolved file staged (edited outside Bough).
    func markResolved(_ entry: StatusEntry) async {
        await mutate { try await $0.runOrThrow(["add", "--", entry.path]) }
    }

    // MARK: - Plumbing

    /// Wrap a git mutation: run it, always refresh, surface errors as banner.
    /// `reloadsHistory` for operations that move HEAD or refs.
    private func mutate(_ operation: (GitRepository) async throws -> Void,
                        reloadsHistory: Bool = false) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation(repository)
        } catch {
            banner = .error(error.localizedDescription)
            Log.git.error("mutation failed: \(String(describing: error), privacy: .public)")
        }
        await refresh()
        async let branchesReload: Void = branches.reload()
        async let stashReload: Void = stash.reload()
        async let tagsReload: Void = tags.reload()
        if reloadsHistory {
            await history.reload()
        }
        _ = await (branchesReload, stashReload, tagsReload)
    }
}
