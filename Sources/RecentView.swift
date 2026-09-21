import SwiftUI
import AppKit

struct RecentView: View {
    @ObservedObject var library: LiveLibrary
    @State private var dateFilterKey = "all"

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private var allSections: [DateSectionModel] {
        let grouped = Dictionary(grouping: library.items) {
            calendar.startOfDay(for: $0.modifiedAt)
        }

        return grouped.keys.sorted(by: >).map { date in
            DateSectionModel(
                date: date,
                items: (grouped[date] ?? []).sorted { $0.modifiedAt > $1.modifiedAt }
            )
        }
    }

    private var displayedSections: [DateSectionModel] {
        dateFilterKey == "all"
            ? allSections
            : allSections.filter { dayKey($0.date) == dateFilterKey }
    }

    private var displayedItems: [LiveItem] {
        displayedSections.flatMap(\.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if displayedSections.isEmpty {
                emptyState
            } else {
                gallery
            }

            if !library.selected.isEmpty {
                selectionBar
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Photo")
                    .font(.system(size: 27, weight: .bold))
                Text("DaVinci 自动监听，也可以手动导入视频。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                library.manualImport()
            } label: {
                Label("导入视频", systemImage: "plus")
            }

            dateMenu

            Button {
                library.toggleSelection(for: displayedItems)
            } label: {
                Label(
                    allDisplayedSelected ? "取消全选" : "全选",
                    systemImage: "checkmark.circle"
                )
            }

            Button {
                library.airdropSelected()
            } label: {
                Label("AirDrop", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.selected.isEmpty)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var dateMenu: some View {
        Menu {
            Button("全部日期") { dateFilterKey = "all" }
            Divider()
            ForEach(allSections) { section in
                Button {
                    dateFilterKey = dayKey(section.date)
                } label: {
                    Text("\(dayTitle(section.date))  ·  \(section.items.count)")
                }
            }
        } label: {
            Label(filterTitle, systemImage: "calendar")
                .frame(minWidth: 96)
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
                ForEach(displayedSections) { section in
                    Section {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: library.thumbnailDensity.gridRange.0,
                                        maximum: library.thumbnailDensity.gridRange.1
                                    ),
                                    spacing: 12
                                )
                            ],
                            spacing: 14
                        ) {
                            ForEach(section.items) { item in
                                LiveCard(
                                    item: item,
                                    selected: library.selected.contains(item.id),
                                    showTechnicalInfo: library.showTechnicalInfo
                                ) {
                                    library.toggle(
                                        item,
                                        orderedItems: displayedItems,
                                        extendRange: NSEvent.modifierFlags.contains(.shift)
                                    )
                                }
                                .contextMenu {
                                    Button("AirDrop 这一条") { library.airdrop([item]) }
                                    Button("在 Finder 中显示") { library.reveal(item) }
                                }
                            }
                        }
                        .padding(.horizontal, 26)
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.bottom, library.selected.isEmpty ? 28 : 102)
        }
    }

    private func sectionHeader(_ section: DateSectionModel) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle(section.date))
                    .font(.system(size: 17, weight: .bold))
                Text("\(section.items.count) 个 Live Photo")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let selected = library.isGroupSelected(section.items)
            Button {
                library.toggleGroup(section.items)
            } label: {
                Label(
                    selected ? "取消本日" : "选择本日",
                    systemImage: selected ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12.5, weight: .semibold))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "livephoto")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)
            Text("还没有 Live Photo")
                .font(.system(size: 18, weight: .semibold))
            Text("把 DaVinci 输出到监听目录，或者手动导入一批视频。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Button {
                library.manualImport()
            } label: {
                Label("导入视频", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionBar: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 30, height: 30)
                    Text("\(library.selected.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("已选择 \(library.selected.count) 个 Live Photo")
                        .font(.system(size: 13, weight: .semibold))
                    Text("可按日期追加，或 Shift 连续选择")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("清除选择") {
                library.selected.removeAll()
            }
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
        .frame(height: 76)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var allDisplayedSelected: Bool {
        let ids = Set(displayedItems.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: library.selected)
    }

    private var filterTitle: String {
        if dateFilterKey == "all" { return "全部日期" }
        return allSections.first { dayKey($0.date) == dateFilterKey }
            .map { dayTitle($0.date) } ?? "全部日期"
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
