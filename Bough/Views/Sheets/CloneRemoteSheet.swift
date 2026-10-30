import SwiftUI

/// Clone sheet: URL + folder name + destination picker; delegates to MainWindowModel.
struct CloneRemoteSheet: View {
    @ObservedObject var viewModel: MainWindowModel
    let onClose: () -> Void

    @State private var url = ""
    @State private var folderName = ""
    @State private var parent = FileManager.default.homeDirectoryForCurrentUser
    @State private var validationError: String?

    private var canClone: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty
            && CloneService.isValidSource(url)
            && !viewModel.isProcessing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("克隆远程仓库")
                .font(.title3.weight(.semibold))
            TextField("仓库地址（https://… 或 git@host:group/repo.git）", text: $url)
                .textFieldStyle(.roundedBorder)
                .onChange(of: url) { _ in
                    folderName = CloneService.suggestedFolderName(for: url)
                    validationError = CloneService.isValidSource(url) ? nil : "地址格式无效"
                }
            HStack {
                TextField("文件夹名", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("选择位置…") { pickParent() }
                Text(parent.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(parent.path)
            }
            if let validationError, !url.isEmpty {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.activity)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("克隆") {
                    let target = url
                    let name = folderName
                    onClose()
                    Task {
                        await viewModel.cloneRepository(url: target,
                                                        folderName: name,
                                                        into: parent)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canClone)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func pickParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "选择克隆目标位置"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            parent = url
        }
    }
}
