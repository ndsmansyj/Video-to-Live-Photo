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
                .font(.system(size: 16, weight: .semibold))

            Divider()

            content
        }
        .padding(20)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @ObservedObject var library: LiveLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("设置")
                        .font(.system(size: 28, weight: .bold))
                    Text("控制监听、文件位置和浏览体验。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                SettingsCard("自动化") {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsToggle(
                            "自动监听 DaVinci 输出目录",
                            subtitle: "文件写入完成后自动生成 Live Photo。",
                            value: Binding(
                                get: { library.isMonitoring },
                                set: { library.setMonitoring($0) }
                            )
                        )

                        settingsToggle(
                            "登录 Mac 后自动启动",
                            subtitle: "安装到“应用程序”后使用最稳定。",
                            value: Binding(
                                get: { library.launchAtLoginEnabled },
                                set: { library.setLaunchAtLogin($0) }
                            )
                        )

                        Text("手动导入始终可用，不受自动监听开关影响。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard("文件夹") {
                    folderRow(
                        title: "监听目录",
                        path: library.inputURL.path,
                        action: library.chooseInputDirectory
                    )

                    Divider()

                    folderRow(
                        title: "输出目录",
                        path: library.outputURL.path,
                        action: library.chooseOutputDirectory
                    )
                }

                SettingsCard("浏览") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("缩略图大小")
                                .font(.system(size: 14.5, weight: .medium))
                            Text("竖屏素材建议用“标准”或“紧凑”。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker(
                            "",
                            selection: Binding(
                                get: { library.thumbnailDensity },
                                set: { library.setThumbnailDensity($0) }
                            )
                        ) {
                            ForEach(ThumbnailDensity.allCases) { density in
                                Text(density.title).tag(density)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }

                    Divider()

                    settingsToggle(
                        "显示技术信息",
                        subtitle: "在缩略图和历史记录里显示分辨率、编码和帧率。",
                        value: Binding(
                            get: { library.showTechnicalInfo },
                            set: { library.setShowTechnicalInfo($0) }
                        )
                    )
                }

                SettingsCard("安全与缓存") {
                    VStack(alignment: .leading, spacing: 12) {
                        safetyRow(
                            "原视频只读",
                            "不会移动、覆盖或删除 DaVinci / 手动导入的源文件。",
                            "lock.shield"
                        )
                        safetyRow(
                            "只清理自己的临时缓存",
                            "AirDrop 使用的 .pvt 临时包超过 24 小时后自动清理。",
                            "clock.arrow.circlepath"
                        )
                        safetyRow(
                            "不接入 Photos 图库",
                            "所有转换都在本地文件夹完成，AirDrop 后直接进入 iPhone。",
                            "photo.on.rectangle.angled"
                        )
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private func settingsToggle(
        _ title: String,
        subtitle: String,
        value: Binding<Bool>
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func folderRow(
        title: String,
        path: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                Text(path)
                    .font(.system(size: 12.5))
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

    private func safetyRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
