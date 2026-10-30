import SwiftUI

/// Reset confirmation: pick soft / mixed / hard with explicit consequences.
struct ResetSheetView: View {
    let commit: Commit
    let onConfirm: (GitRepository.ResetMode) -> Void

    @State private var mode: GitRepository.ResetMode = .mixed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重置当前分支")
                .font(.title3.weight(.semibold))
            Text("将当前分支移动到 \(commit.shortSha)「\(commit.subject)」")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("模式", selection: $mode) {
                Text("Soft（保留索引与工作区）").tag(GitRepository.ResetMode.soft)
                Text("Mixed（保留工作区，重置索引）").tag(GitRepository.ResetMode.mixed)
                Text("Hard（丢弃所有未提交与之后的提交）").tag(GitRepository.ResetMode.hard)
            }
            .pickerStyle(.radioGroup)
            if mode == .hard {
                Label("hard 重置不可撤销，之后的提交将从分支上移除", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("重置", role: .destructive) {
                    onConfirm(mode)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
