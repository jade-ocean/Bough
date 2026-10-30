import SwiftUI

/// Commit message editor + amend/sign picker + identity hint.
struct CommitComposer: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = model.identityHint {
                Label(hint, systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.commitMessage)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 56, maxHeight: 110)
                    .border(Color(nsColor: .separatorColor))
                if model.commitMessage.isEmpty {
                    Text("提交信息（第一行为摘要）")
                        .foregroundStyle(.tertiary)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            optionsRow
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var optionsRow: some View {
        HStack(spacing: 14) {
            Toggle("修改上次提交", isOn: Binding(
                get: { model.isAmendEnabled },
                set: { value in Task { await model.setAmend(value) } }))
                .disabled(model.status.isUnborn)
            Picker("签名", selection: $model.signing) {
                ForEach(CommitSigning.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .frame(width: 190)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.commit() }
            } label: {
                Text(model.isAmendEnabled ? "修改提交" : "提交")
                    .frame(width: 88)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canCommit)
        }
    }
}
