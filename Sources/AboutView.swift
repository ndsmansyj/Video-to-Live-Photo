import SwiftUI
import AppKit

struct AboutView: View {
    private let projectURL = URL(string: "https://github.com/ndsmansyj/Video-to-Live-Photo")!

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 6) {
                    Text("Video to Live Turbo")
                        .font(.system(size: 28, weight: .semibold))

                    Text("把普通视频快速变成 iPhone Live Photo。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text("本机处理 · 不修改原视频 · 支持片段与封面调整、批量生成和 AirDrop")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Link(destination: projectURL) {
                    Label("打开项目主页", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            }
            .padding(.horizontal, 48)
            .padding(.vertical, 38)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .frame(maxWidth: 620)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }
}
