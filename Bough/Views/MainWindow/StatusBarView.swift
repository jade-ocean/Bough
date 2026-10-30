import SwiftUI

/// Bottom status bar: repo path + branch + activity/progress.
struct StatusBarView: View {
    private let windowModel: MainWindowModel
    @ObservedObject private var workspaceModel: WorkspaceModel
    private let workspace: MainWindowModel.Workspace

    init(workspace: MainWindowModel.Workspace, windowModel: MainWindowModel) {
        self.workspace = workspace
        self.windowModel = windowModel
        self._workspaceModel = ObservedObject(wrappedValue: workspace.workspaceModel)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(workspace.root.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(workspace.root.path)
            Spacer()
            branchInfo
            if windowModel.isProcessing || workspaceModel.isBusy {
                ProgressView().controlSize(.small)
                Text(windowModel.isProcessing ? windowModel.activity : "git 执行中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var branchInfo: some View {
        if let branch = workspaceModel.status.branch {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(branch)
                if workspaceModel.status.ahead > 0 || workspaceModel.status.behind > 0 {
                    Text("↑\(workspaceModel.status.ahead) ↓\(workspaceModel.status.behind)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
