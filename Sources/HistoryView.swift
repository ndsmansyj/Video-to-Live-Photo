import SwiftUI

struct HistoryPanel: View {
    @ObservedObject var library: LiveLibrary
    let onCollapse: () -> Void

    @State private var search = ""
    @State private var editingItem: LiveItem?
    @State private var collapsedDays: Set<Date> = []

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private var filtered: [LiveItem] {
        guard !search.isEmpty else { return library.items }
        return library.items.filter {
            $0.baseName.localizedCaseInsensitiveContains(search)
                || $0.detailsText.localizedCaseInsensitiveContains(search)
        }
    }

    private var sections: [DateSectionModel] {
        let grouped = Dictionary(grouping: filtered) {
            calendar.startOfDay(for: $0.modifiedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            DateSectionModel(
                date: day,
                items: (grouped[day] ?? []).sorted { $0.modifiedAt > $1.modifiedAt }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("历史")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Button {
                    library.revealOutput()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("打开输出文件夹")

                Button(action: onCollapse) {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help("收起历史")
            }
            .padding(.horizontal, 14)
            .padding(.top, 15)
            .padding(.bottom, 10)

            if !library.items.isEmpty {
                TextField("搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            Divider()

            if library.items.isEmpty {
                emptyHistory
            } else if filtered.isEmpty {
                emptySearch
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sections) { section in
                            historySection(section)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
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

    private func historySection(_ section: DateSectionModel) -> some View {
        let day = calendar.startOfDay(for: section.date)
        let collapsed = search.isEmpty && collapsedDays.contains(day)

        return VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    if collapsed {
                        collapsedDays.remove(day)
                    } else {
                        collapsedDays.insert(day)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(dayTitle(day))
                        .font(.system(size: 12.5, weight: .semibold))

                    Text("\(section.items.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())

                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 2) {
                    ForEach(section.items) { item in
                        historyRow(item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func historyRow(_ item: LiveItem) -> some View {
        HStack(spacing: 10) {
            ThumbnailView(url: item.imageURL)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.baseName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .help(item.baseName)

                Text(item.modifiedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                library.airdrop([item])
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderless)
            .help("AirDrop")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contextMenu {
            if item.canEdit {
                Button("重新调整…") { editingItem = item }
            }
            Button("AirDrop") { library.airdrop([item]) }
            Button("在 Finder 中显示") { library.reveal(item) }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("还没有历史记录")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearch: some View {
        VStack(spacing: 8) {
            Text("没有找到相关记录")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("清除搜索") { search = "" }
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat =
            calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            ? "M月d日 EEEE"
            : "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}

struct HistoryView: View {
    @ObservedObject var library: LiveLibrary

    var body: some View {
        HistoryPanel(library: library, onCollapse: {})
    }
}
