import SwiftUI

/// App settings (Bough > 设置…, Cmd+,): sync default, diff typography,
/// commit signing default. Persisted via AppPreferences (UserDefaults).
struct SettingsView: View {
    @State private var pullStrategy = AppPreferences.defaultPullStrategy
    @State private var fontSize = AppPreferences.diffFontSize
    @State private var signing = AppPreferences.defaultSigning

    var body: some View {
        Form {
            Section("远程同步") {
                Picker("默认 Pull 策略", selection: $pullStrategy) {
                    Text("merge").tag(GitRepository.PullStrategy.merge)
                    Text("rebase").teamRebaseTag
                }
                .onChange(of: pullStrategy) { newValue in
                    AppPreferences.defaultPullStrategy = newValue
                }
                Text("「Pull（默认）」菜单项与多仓库批量 Pull 使用此策略")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Diff 阅读") {
                LabeledContent("字号") {
                    HStack {
                        Slider(value: $fontSize, in: 10...16, step: 1) {
                            Text("Diff 字号")
                        }
                        .frame(width: 200)
                        .onChange(of: fontSize) { newValue in
                            AppPreferences.diffFontSize = newValue
                        }
                        Text("\(Int(fontSize)) pt")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("即时生效，作用于内联与并排 diff 正文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("提交") {
                Picker("签名默认方式", selection: $signing) {
                    ForEach(CommitSigning.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .onChange(of: signing) { newValue in
                    AppPreferences.defaultSigning = newValue
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

private extension Text {
    /// Small helper keeping the picker options visually uniform.
    var teamRebaseTag: some View { Text("rebase") }
}
