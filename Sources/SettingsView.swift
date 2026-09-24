import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))

            Divider()

            content
        }
        .padding(20)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @ObservedObject var library: LiveLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("设置")
                    .font(.system(size: 26, weight: .semibold))

                SettingsCard("输出位置") {
                    folderRow(
                        title: "输出文件夹",
                        path: library.outputURL.path,
                        action: library.chooseOutputDirectory
                    )
                }

                SettingsCard("自动化") {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsToggle(
                            "自动转换文件夹中的新视频",
                            subtitle: "App 打开时扫描，运行期间持续检测新视频。",
                            value: Binding(
                                get: { library.isMonitoring },
                                set: { library.setMonitoring($0) }
                            )
                        )

                        Divider()

                        folderRow(
                            title: "自动转换文件夹",
                            path: library.inputURL.path,
                            action: library.chooseInputDirectory
                        )

                        Divider()

                        settingsToggle(
                            "登录 Mac 后自动启动",
                            subtitle: "适合需要持续自动转换的工作流。",
                            value: Binding(
                                get: { library.launchAtLoginEnabled },
                                set: { library.setLaunchAtLogin($0) }
                            )
                        )
                    }
                }

                SettingsCard("浏览") {
                    settingsToggle(
                        "显示技术信息",
                        subtitle: "显示分辨率、编码和帧率。",
                        value: Binding(
                            get: { library.showTechnicalInfo },
                            set: { library.setShowTechnicalInfo($0) }
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("所有转换均在本机完成，不移动、覆盖或删除原视频。")

                    Label(
                        "支持 Agent 与脚本直接调用转换核心（CLI）。",
                        systemImage: "terminal"
                    )
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func settingsToggle(
        _ title: String,
        subtitle: String,
        value: Binding<Bool>
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity)
    }

    private func folderRow(
        title: String,
        path: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("更改…", action: action)
                .controlSize(.large)
        }
        .padding(.vertical, 2)
    }
}
