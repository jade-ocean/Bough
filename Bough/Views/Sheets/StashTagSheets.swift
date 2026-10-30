import SwiftUI

/// Stash creation sheet.
struct NewStashSheet: View {
    @ObservedObject var model: WorkspaceModel
    let onClose: () -> Void

    @State private var message = ""
    @State private var includeUntracked = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("暂存当前更改（Stash）")
                .font(.title3.weight(.semibold))
            TextField("备注（可选，默认 WIP）", text: $message)
                .textFieldStyle(.roundedBorder)
            Toggle("包含未跟踪文件", isOn: $includeUntracked)
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Stash") {
                    Task {
                        await model.stashCreate(message: message, includeUntracked: includeUntracked)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// Tag creation sheet: lightweight or annotated.
struct NewTagSheet: View {
    @ObservedObject var model: WorkspaceModel
    /// Target commit; nil = HEAD.
    let target: Commit?
    let onClose: () -> Void

    @State private var name = ""
    @State private var message = ""
    @State private var annotated = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建标签")
                .font(.title3.weight(.semibold))
            Text(target.map { "指向提交 \($0.shortSha)「\($0.subject)」" } ?? "指向 HEAD")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("标签名（如 v1.0.0）", text: $name)
                .textFieldStyle(.roundedBorder)
            Toggle("附注标签（含说明信息）", isOn: $annotated)
            if annotated {
                TextField("标签说明", text: $message)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    Task {
                        await model.createTag(name, message: message,
                                              target: target?.sha, annotated: annotated)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || (annotated && message.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Simplified interactive rebase: keep / drop / reorder commits above a base.
struct InteractiveRebaseSheet: View {
    @ObservedObject var model: WorkspaceModel
    let base: Commit
    let onClose: () -> Void

    @State private var steps: [GitRepository.RebaseStep] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("交互式 Rebase（简化版）")
                .font(.title3.weight(.semibold))
            Text("将 \(base.shortSha) 之后的提交重新编排：可下拖放排序或标记丢弃")
                .font(.callout)
                .foregroundStyle(.secondary)
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else {
                stepList
            }
            HStack {
                Text("丢弃的提交将从分支移除（可通过 reflog 找回）；改写只改信息不改内容")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("执行 Rebase") {
                    Task {
                        await model.interactiveRebase(base: base, steps: steps)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || steps.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
        .task { await loadPlan() }
    }

    private var stepList: some View {
        List {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    Text(step.sha.prefix(7))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(step.subject)
                        .lineLimit(1)
                        .opacity(step.dropped ? 0.4 : 1)
                    Spacer()
                    Button {
                        moveUp(index)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    Button {
                        moveDown(index)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == steps.count - 1)
                    Toggle("丢弃", isOn: Binding(
                        get: { steps[index].dropped },
                        set: { steps[index].dropped = $0 }))
                    .toggleStyle(.checkbox)
                    Toggle("改写", isOn: Binding(
                        get: { steps[index].newMessage != nil },
                        set: { wants in
                            steps[index].newMessage = wants
                                ? (steps[index].newMessage ?? steps[index].subject)
                                : nil
                        }))
                    .toggleStyle(.checkbox)
                    .help("改写此提交的信息（reword）")
                }
                if steps[index].newMessage != nil {
                    TextField("新提交信息", text: Binding(
                        get: { steps[index].newMessage ?? "" },
                        set: { steps[index].newMessage = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }
            }
        }
        .listStyle(.plain)
    }

    private func loadPlan() async {
        isLoading = true
        defer { isLoading = false }
        do {
            steps = try await model.repository.rebasePlan(base: base.sha)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        steps.swapAt(index, index - 1)
    }

    private func moveDown(_ index: Int) {
        guard index < steps.count - 1 else { return }
        steps.swapAt(index, index + 1)
    }
}
