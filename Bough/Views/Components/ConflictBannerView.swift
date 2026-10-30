import SwiftUI

/// Orange banner shown while merge/rebase conflicts are unresolved.
/// Full conflict-resolution UI arrives in Phase 5; abort/continue cover phase 4.
struct ConflictBannerView: View {
    @ObservedObject var model: WorkspaceModel
    let onResolve: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("检测到 \(model.status.unmerged.count) 个冲突文件")
                .font(.callout.weight(.medium))
            Spacer()
            Button("解决冲突…") { onResolve() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button("继续 Rebase") {
                Task { await model.continueRebase() }
            }
            .controlSize(.small)
            Button("中止 Rebase") {
                Task { await model.abortRebase() }
            }
            .controlSize(.small)
            Button("中止 Merge") {
                Task { await model.abortMerge() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
    }
}
