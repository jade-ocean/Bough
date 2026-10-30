import SwiftUI

/// Destructive-action confirmation sheet for discard/delete.
struct DiscardConfirmation: View {
    let entries: [StatusEntry]
    let onConfirm: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("确认放弃更改？")
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        Text(entry.path)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 180)
            HStack {
                Spacer()
                Button("取消") { onConfirm(false) }
                    .keyboardShortcut(.cancelAction)
                Button("放弃更改", role: .destructive) { onConfirm(true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entries.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var description: String {
        let untrackedCount = entries.filter(\.isUntracked).count
        let trackedCount = entries.count - untrackedCount
        var parts: [String] = []
        if trackedCount > 0 {
            parts.append("\(trackedCount) 个已跟踪文件的更改将回退到 HEAD（含已暂存内容）")
        }
        if untrackedCount > 0 {
            parts.append("\(untrackedCount) 个未跟踪文件将被永久删除")
        }
        return parts.joined(separator: "；") + "。此操作不可撤销。"
    }
}
