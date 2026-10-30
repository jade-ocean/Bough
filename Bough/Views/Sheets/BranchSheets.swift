import SwiftUI

/// Branch creation sheet: name + optional start point + checkout-now toggle.
struct NewBranchSheet: View {
    @ObservedObject var model: WorkspaceModel
    /// Prefilled start point (branch name or sha); empty = HEAD.
    let startPointHint: String?
    let onClose: () -> Void

    @State private var name = ""
    @State private var startPoint = ""
    @State private var checkoutNow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建分支")
                .font(.title3.weight(.semibold))
            TextField("分支名（如 feature/login）", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("起点（分支名或 SHA，默认 HEAD）", text: $startPoint)
                .textFieldStyle(.roundedBorder)
            Toggle("创建后立即检出", isOn: $checkoutNow)
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    let start = startPoint.isEmpty ? nil : startPoint
                    Task {
                        await model.createBranch(name, from: start, checkout: checkoutNow)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { startPoint = startPointHint ?? "" }
    }
}

/// Branch rename sheet.
struct RenameBranchSheet: View {
    @ObservedObject var model: WorkspaceModel
    let branch: Branch
    let onClose: () -> Void

    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名分支")
                .font(.title3.weight(.semibold))
            Text("将「\(branch.name)」重命名为：")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("新名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("重命名") {
                    Task {
                        await model.rename(branch, to: newName)
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { newName = branch.name }
    }
}

/// Remote add/edit sheet with per-repo SSL config for self-signed certificates.
struct RemoteEditorSheet: View {
    @ObservedObject var model: WorkspaceModel
    /// Existing remote to edit, nil = create new.
    let remote: RemoteInfo?
    let onClose: () -> Void

    @State private var name = ""
    @State private var url = ""
    @State private var sslVerify = true
    @State private var caPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(remote == nil ? "添加远程仓库" : "编辑远程仓库")
                .font(.title3.weight(.semibold))
            if remote == nil {
                TextField("名称（如 origin）", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("URL（https:// 或 ssh:// 或 git@host:path）", text: $url)
                .textFieldStyle(.roundedBorder)
            Divider()
            Toggle("校验 SSL 证书（自签证书环境可关闭，风险自负）", isOn: $sslVerify)
            HStack {
                Text("自签 CA 证书路径")
                    .foregroundStyle(.secondary)
                TextField("/path/to/ca.pem", text: $caPath)
                    .textFieldStyle(.roundedBorder)
            }
            if !sslVerify {
                Label("关闭校验将使连接可被中间人攻击，仅建议隔离内网使用",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            let config = await model.repository.sslConfig()
            sslVerify = config.verify
            caPath = config.caInfoPath ?? ""
            if let remote {
                name = remote.name
                url = remote.url
            }
        }
    }

    private func save() async {
        if remote == nil, !name.isEmpty {
            await model.addRemote(name: name, url: url)
        }
        do {
            try await model.repository.setSSLConfig(verify: sslVerify, caInfoPath: caPath.isEmpty ? nil : caPath)
        } catch {
            model.banner = .error(error.localizedDescription)
        }
        onClose()
    }
}
