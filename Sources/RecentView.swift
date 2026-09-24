import SwiftUI
import AppKit

struct RecentView: View {
    @ObservedObject var library: LiveLibrary

    @AppStorage("historyPanelExpanded") private var historyExpanded = true
    @State private var editingItem: LiveItem?
    @State private var editingPending: PendingVideo?
    @State private var isDropTarget = false

    private var sessionItems: [LiveItem] {
        library.sessionItems.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 74), spacing: 12),
            count: max(3, library.thumbnailColumnCount)
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                workspaceHeader
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        importWorkspace

                        if let message = library.operationMessage {
                            operationBanner(message)
                        }

                        if !library.pendingVideos.isEmpty {
                            pendingSection
                        }

                        generatedSection
                    }
                    .padding(24)
                    .padding(.bottom, library.selected.isEmpty ? 12 : 76)
                }

                if !library.selected.isEmpty {
                    selectionBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if historyExpanded {
                Divider()
                HistoryPanel(
                    library: library,
                    onCollapse: { historyExpanded = false }
                )
                .frame(width: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: historyExpanded)
        .sheet(item: $editingPending) { item in
            ClipEditorView(
                sourceURL: item.sourceURL,
                title: item.baseName,
                coverSeconds: item.coverSeconds,
                clipStart: item.clipStart,
                clipDuration: item.clipDuration,
                actionTitle: "保存设置"
            ) { cover, start, duration in
                library.updatePending(
                    id: item.id,
                    coverSeconds: cover,
                    clipStart: start,
                    clipDuration: duration
                )
                return true
            }
        }
        .sheet(item: $editingItem) { item in
            if let source = item.sourceURL {
                ClipEditorView(
                    sourceURL: source,
                    title: item.baseName,
                    coverSeconds: item.coverSeconds,
                    clipStart: item.clipStart,
                    clipDuration: item.clipDuration,
                    actionTitle: "重新生成"
                ) { cover, start, duration in
                    await library.regenerate(
                        item,
                        coverSeconds: cover,
                        clipStart: start,
                        clipDuration: duration
                    )
                }
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("转换工作区")
                    .font(.system(size: 26, weight: .semibold))
                Text("Video → Live Photo → iPhone")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !historyExpanded {
                Button {
                    historyExpanded = true
                } label: {
                    Label("历史", systemImage: "sidebar.right")
                }
                .help("打开历史")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 17)
    }

    private var importWorkspace: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isDropTarget
                            ? Color.accentColor.opacity(0.08)
                            : Color(nsColor: .controlBackgroundColor)
                    )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDropTarget
                            ? Color.accentColor.opacity(0.75)
                            : Color.primary.opacity(0.10),
                        style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                    )

                HStack(spacing: 18) {
                    Image(systemName: library.isProcessing ? "livephoto.play" : "film.stack")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(library.isProcessing ? Color.accentColor : Color.secondary)
                        .frame(width: 48)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(library.isProcessing ? library.statusText : "导入视频")
                            .font(.system(size: 17, weight: .semibold))

                        Text(
                            library.isProcessing
                                ? "正在生成，完成后会出现在“本次生成”。"
                                : "拖入视频，调整后生成 Live Photo。"
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if library.isProcessing {
                        ProgressView().controlSize(.small)
                    } else if library.pendingVideos.isEmpty {
                        Button {
                            library.manualImport()
                        } label: {
                            Label("选择视频…", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button {
                            library.manualImport()
                        } label: {
                            Label("选择视频…", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, 22)
            }
            .frame(height: 118)
            .dropDestination(for: URL.self) { urls, _ in
                library.importVideos(urls)
                return !urls.isEmpty
            } isTargeted: { isDropTarget = $0 }

            if library.isMonitoring {
                HStack(spacing: 7) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("自动转换文件夹已开启")
                        .font(.system(size: 11.5, weight: .medium))
                    Text(library.inputURL.lastPathComponent)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("待生成")
                    .font(.system(size: 17, weight: .semibold))

                Text("\(library.pendingVideos.count)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                Text("点击画面调整片段与封面")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                Spacer()

                BatchSoundToggle(isOn: $library.manualIncludeAudio)
                    .disabled(library.isProcessing)

                Button {
                    library.generatePending()
                } label: {
                    Label(
                        library.pendingVideos.count == 1
                            ? "生成 Live Photo"
                            : "生成 \(library.pendingVideos.count) 个 Live Photo",
                        systemImage: "sparkles.rectangle.stack"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isProcessing)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(library.pendingVideos) { item in
                    PendingVideoCard(
                        item: item,
                        onEdit: { editingPending = item },
                        onRemove: { library.removePending(item.id) }
                    )
                    .contextMenu {
                        Button("调整片段与封面…") { editingPending = item }
                        Button("移除") { library.removePending(item.id) }
                    }
                }
            }
        }
    }

    private var generatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            generatedHeader

            if !sessionItems.isEmpty {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(sessionItems) { item in
                        LiveCard(
                            item: item,
                            selected: library.selected.contains(item.id),
                            showTechnicalInfo: library.showTechnicalInfo,
                            onToggle: {
                                library.toggle(
                                    item,
                                    orderedItems: sessionItems,
                                    extendRange: NSEvent.modifierFlags.contains(.shift)
                                )
                            }
                        )
                        .contextMenu {
                            if item.canEdit {
                                Button("重新调整…") { editingItem = item }
                            }
                            Button("AirDrop 这一条") { library.airdrop([item]) }
                            Button("在 Finder 中显示") { library.reveal(item) }
                        }
                    }
                }
            } else {
                Text("生成的 Live Photo 会显示在这里。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
            }
        }
    }

    private var generatedHeader: some View {
        HStack(spacing: 12) {
            Text("本次生成")
                .font(.system(size: 17, weight: .semibold))

            if !sessionItems.isEmpty {
                Text("\(sessionItems.count)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Spacer()

            if !sessionItems.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.grid.3x2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { library.thumbnailZoom },
                            set: { library.setThumbnailZoom($0) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 110)
                    .help("缩略图大小")

                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Button {
                    library.toggleSelection(for: sessionItems)
                } label: {
                    Label(allSessionSelected ? "取消全选" : "全选", systemImage: "checkmark.circle")
                }
            }
        }
    }

    private func operationBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: library.failedSources.isEmpty ? "info.circle" : "exclamationmark.triangle")
                .foregroundStyle(
                    library.failedSources.isEmpty
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color.orange
                )

            Text(message)
                .font(.system(size: 12.5))
                .lineLimit(2)

            Spacer()

            if !library.failedSources.isEmpty {
                Button("重试失败项") { library.retryFailed() }
                    .buttonStyle(.borderless)
            }

            Button { library.operationMessage = nil } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text("已选 \(library.selected.count) 项")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("取消选择") { library.clearSelection() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button {
                library.airdropSelected()
            } label: {
                Label("AirDrop 到 iPhone", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var allSessionSelected: Bool {
        let ids = Set(sessionItems.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: library.selected)
    }
}
