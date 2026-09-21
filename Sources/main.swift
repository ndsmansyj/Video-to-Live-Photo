import SwiftUI
import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

struct LiveItem: Identifiable, Hashable {
    let id: String
    let baseName: String
    let imageURL: URL
    let videoURL: URL
    let modifiedAt: Date
    let durationText: String
    let detailsText: String
}

@MainActor
final class LiveLibrary: ObservableObject {
    @Published var items: [LiveItem] = []
    @Published var selected: Set<String> = []
    @Published var isMonitoring = true
    @Published var isProcessing = false
    @Published var statusText = "准备中"
    @Published var inputURL: URL
    @Published var outputURL: URL
    @Published var launchAtLoginEnabled = false
    @Published var thumbnailDensity: String
    @Published var showTechnicalInfo: Bool

    var processedURL: URL {
        outputURL.deletingLastPathComponent().appendingPathComponent("Processed", isDirectory: true)
    }

    private var timer: Timer?
    private var observedSizes: [String: Int64] = [:]
    private var activeInputs: Set<String> = []
    private var selectionAnchorID: String?

    init() {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultRoot = home.appendingPathComponent("Movies/SPP_Live_Export", isDirectory: true)
        self.inputURL = URL(fileURLWithPath: defaults.string(forKey: "inputPath") ?? defaultRoot.appendingPathComponent("Input").path, isDirectory: true)
        self.outputURL = URL(fileURLWithPath: defaults.string(forKey: "outputPath") ?? defaultRoot.appendingPathComponent("Output").path, isDirectory: true)
        self.thumbnailDensity = defaults.string(forKey: "thumbnailDensity") ?? "standard"
        self.showTechnicalInfo = defaults.object(forKey: "showTechnicalInfo") == nil ? true : defaults.bool(forKey: "showTechnicalInfo")
        self.isMonitoring = defaults.object(forKey: "monitoringEnabled") == nil ? true : defaults.bool(forKey: "monitoringEnabled")
        if #available(macOS 13.0, *) {
            self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }

        prepareFolders()
        refresh()
        cleanupOldAirDropCache()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if self.isMonitoring { self.scanPendingInputs() }
            }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: outputURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let heics = urls.filter { $0.pathExtension.lowercased() == "heic" }
        var next: [LiveItem] = []

        for image in heics {
            let stem = image.deletingPathExtension().lastPathComponent
            let movie = outputURL.appendingPathComponent(stem).appendingPathExtension("mov")
            guard fm.fileExists(atPath: movie.path) else { continue }
            let vals = try? image.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = vals?.contentModificationDate ?? .distantPast
            let base = stem
                .replacingOccurrences(of: #"_LIVE(?:_\d+)?$"#, with: "", options: .regularExpression)
            let media = probe(movie)
            next.append(LiveItem(
                id: stem,
                baseName: base,
                imageURL: image,
                videoURL: movie,
                modifiedAt: modified,
                durationText: media.duration,
                detailsText: media.details
            ))
        }

        items = next.sorted { $0.modifiedAt > $1.modifiedAt }
        selected = selected.intersection(Set(items.map(\.id)))
        statusText = isProcessing ? "正在生成 Live…" : (isMonitoring ? "正在监听 DaVinci" : "监听已暂停")
    }

    func toggle(_ item: LiveItem, orderedItems: [LiveItem], extendRange: Bool = false) {
        if extendRange,
           let anchor = selectionAnchorID,
           let a = orderedItems.firstIndex(where: { $0.id == anchor }),
           let b = orderedItems.firstIndex(where: { $0.id == item.id }) {
            let range = min(a, b)...max(a, b)
            selected.formUnion(orderedItems[range].map(\.id))
        } else {
            if selected.contains(item.id) { selected.remove(item.id) }
            else { selected.insert(item.id) }
        }
        selectionAnchorID = item.id
    }

    func toggleSelection(for visibleItems: [LiveItem]) {
        let ids = Set(visibleItems.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) }
        else { selected.formUnion(ids) }
    }

    func toggleGroup(_ groupItems: [LiveItem]) {
        let ids = Set(groupItems.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) }
        else { selected.formUnion(ids) }
    }

    func isGroupSelected(_ groupItems: [LiveItem]) -> Bool {
        let ids = Set(groupItems.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selected)
    }

    var selectedItems: [LiveItem] {
        items.filter { selected.contains($0.id) }
    }

    func airdropSelected() {
        airdrop(selectedItems)
    }

    func airdrop(_ picks: [LiveItem]) {
        guard !picks.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }

        do {
            let packages = try picks.map { try makeLivePhotoPackage(for: $0) }
            guard service.canPerform(withItems: packages) else {
                statusText = "AirDrop 无法处理 Live Photo Bundle"
                return
            }
            statusText = "准备 AirDrop \(packages.count) 个 Live Photo"
            service.perform(withItems: packages)
        } catch {
            statusText = "Live Photo Bundle 生成失败"
        }
    }

    func revealInput() { NSWorkspace.shared.open(inputURL) }
    func revealOutput() { NSWorkspace.shared.open(outputURL) }
    func reveal(_ item: LiveItem) { NSWorkspace.shared.activateFileViewerSelecting([item.videoURL]) }

    func manualImport() {
        let panel = NSOpenPanel()
        panel.title = "导入视频生成 Live Photo"
        panel.message = "可多选。原视频只读取，不移动、不修改。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let urls = panel.urls.filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                isProcessing = true
                statusText = "手动导入 \(url.lastPathComponent)"
                await process(url)
            }
        }
    }

    func setMonitoring(_ enabled: Bool) {
        isMonitoring = enabled
        UserDefaults.standard.set(enabled, forKey: "monitoringEnabled")
        statusText = enabled ? "正在监听 DaVinci" : "监听已暂停"
    }

    func chooseInputDirectory() {
        guard let url = chooseDirectory(title: "选择 DaVinci 监听目录", current: inputURL) else { return }
        inputURL = url
        UserDefaults.standard.set(url.path, forKey: "inputPath")
        observedSizes.removeAll()
        prepareFolders()
    }

    func chooseOutputDirectory() {
        guard let url = chooseDirectory(title: "选择 Live Photo 输出目录", current: outputURL) else { return }
        outputURL = url
        UserDefaults.standard.set(url.path, forKey: "outputPath")
        prepareFolders()
        refresh()
    }

    func setThumbnailDensity(_ value: String) {
        thumbnailDensity = value
        UserDefaults.standard.set(value, forKey: "thumbnailDensity")
    }

    func setShowTechnicalInfo(_ enabled: Bool) {
        showTechnicalInfo = enabled
        UserDefaults.standard.set(enabled, forKey: "showTechnicalInfo")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            statusText = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    private func chooseDirectory(title: String, current: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.directoryURL = current
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func prepareFolders() {
        let fm = FileManager.default
        try? fm.createDirectory(at: inputURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: processedURL, withIntermediateDirectories: true)
    }


    private func scanPendingInputs() {
        guard !isProcessing else { return }
        let fm = FileManager.default
        let inputs = (try? fm.contentsOfDirectory(
            at: inputURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let videos = inputs.filter {
            ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased())
        }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }

        for video in videos {
            let key = video.path
            if activeInputs.contains(key) || isMarkedProcessed(video) { continue }

            let values = try? video.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)
            guard size > 0 else { continue }

            if observedSizes[key] == size {
                activeInputs.insert(key)
                isProcessing = true
                statusText = "正在生成 \(video.lastPathComponent)"
                Task { await process(video) }
                return
            } else {
                observedSizes[key] = size
            }
        }
    }

    private func process(_ source: URL) async {
        defer {
            activeInputs.remove(source.path)
            isProcessing = false
            refresh()
        }

        guard let tool = bundledToolURL(), FileManager.default.isExecutableFile(atPath: tool.path) else {
            statusText = "转换器缺失"
            return
        }

        let task = Process()
        task.executableURL = tool
        task.arguments = [source.path, outputURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let raw = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            guard task.terminationStatus == 0,
                  let line = raw.split(separator: "\n").map(String.init).last(where: { $0.hasPrefix("OK\t") }) else {
                statusText = "转换失败"
                return
            }

            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 4 else {
                statusText = "转换结果异常"
                return
            }

            let heic = outputURL.appendingPathComponent(parts[2])
            let mov = outputURL.appendingPathComponent(parts[3])

            writeMarker(source: source, heic: heic.lastPathComponent, mov: mov.lastPathComponent)
            statusText = "Live 已生成"
        } catch {
            statusText = "转换器启动失败"
        }
    }

    private func bundledToolURL() -> URL? {
        Bundle.main.url(forResource: "spp-live-export", withExtension: nil)
    }


    private func cleanupOldAirDropCache() {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.songpanpan.SPPLiveExport/AirDrop", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            if modified < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    private func makeLivePhotoPackage(for item: LiveItem) throws -> URL {
        let fm = FileManager.default
        let cacheRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.songpanpan.SPPLiveExport/AirDrop", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let safeName = item.baseName.isEmpty ? item.id : item.baseName
        let packageURL = cacheRoot.appendingPathComponent(safeName).appendingPathExtension("pvt")
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let stillURL = packageURL.appendingPathComponent(safeName).appendingPathExtension("HEIC")
        let motionURL = packageURL.appendingPathComponent(safeName).appendingPathExtension("MOV")
        try fm.copyItem(at: item.imageURL, to: stillURL)
        try fm.copyItem(at: item.videoURL, to: motionURL)

        let metadata = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PFVideoComplementMetadataVersionKey</key>
          <string>1</string>
        </dict>
        </plist>
        """
        try metadata.write(
            to: packageURL.appendingPathComponent("metadata.plist"),
            atomically: true,
            encoding: .utf8
        )

        return packageURL
    }

    private func markerURL(_ source: URL) -> URL {
        processedURL.appendingPathComponent(source.lastPathComponent + ".done")
    }

    private func isMarkedProcessed(_ source: URL) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(source).path)
    }

    private func writeMarker(source: URL, heic: String, mov: String) {
        let text = """
        source=\(source.path)
        processed_at=\(ISO8601DateFormatter().string(from: Date()))
        heic=\(heic)
        mov=\(mov)
        engine=SPP Live Export.app
        """
        try? text.write(to: markerURL(source), atomically: true, encoding: .utf8)
    }

    private func probe(_ url: URL) -> (duration: String, details: String) {
        let candidates = ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe"]
        guard let ffprobe = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return ("Live Photo", "HEIC + MOV")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffprobe)
        task.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,r_frame_rate:format=duration",
            "-of", "default=nw=1:nk=0",
            url.path
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let raw = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            var codec = "", width = "", height = "", fps = "", duration = ""
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "codec_name": codec = parts[1].uppercased()
                case "width": width = parts[1]
                case "height": height = parts[1]
                case "r_frame_rate": fps = friendlyFPS(parts[1])
                case "duration": duration = parts[1]
                default: break
                }
            }
            let d = Double(duration) ?? 0
            let durationText = d > 0 ? String(format: "%.2fs", d) : "Live Photo"
            let dim = (!width.isEmpty && !height.isEmpty) ? "\(width)×\(height)" : "Live"
            let detail = [dim, codec, fps.isEmpty ? nil : "\(fps)fps"].compactMap { $0 }.joined(separator: " · ")
            return (durationText, detail)
        } catch {
            return ("Live Photo", "HEIC + MOV")
        }
    }

    private func friendlyFPS(_ raw: String) -> String {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let a = Double(parts[0]), let b = Double(parts[1]), b != 0 else { return raw }
        let v = a / b
        if abs(v.rounded() - v) < 0.02 { return String(Int(v.rounded())) }
        return String(format: "%.2f", v)
    }
}

struct ThumbnailView: View {
    let url: URL
    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [.black.opacity(0.82), .gray.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "livephoto")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }
}

struct LiveCard: View {
    let item: LiveItem
    let selected: Bool
    let showTechnicalInfo: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView(url: item.imageURL)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    ZStack {
                        Circle()
                            .fill(selected ? Color.accentColor : Color.black.opacity(0.34))
                            .frame(width: 27, height: 27)
                        Image(systemName: selected ? "checkmark" : "circle")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(10)

                    VStack {
                        Spacer()
                        HStack {
                            Label(item.durationText, systemImage: "livephoto")
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.52), in: Capsule())
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(9)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.baseName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if showTechnicalInfo {
                        Text(item.detailsText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor.opacity(0.95) : Color.primary.opacity(0.07),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct DateSectionModel: Identifiable {
    let date: Date
    let items: [LiveItem]
    var id: Date { date }
}

enum AppPage: String, CaseIterable {
    case recent
    case history
    case settings
}

struct Sidebar: View {
    @ObservedObject var library: LiveLibrary
    @Binding var page: AppPage

    private func navButton(_ target: AppPage, _ title: String, _ icon: String) -> some View {
        Button {
            page = target
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: page == target ? .semibold : .regular))
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    page == target ? Color.primary.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(page == target ? .primary : .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SPP")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Live Export")
                    .font(.system(size: 22, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 3) {
                navButton(.recent, "最近生成", "rectangle.stack.fill")
                navButton(.history, "处理历史", "clock.arrow.circlepath")
                navButton(.settings, "设置", "slider.horizontal.3")
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(library.isMonitoring ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(library.statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }
                Text(library.inputURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Button("输入目录") { library.revealInput() }
                    Button("输出目录") { library.revealOutput() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }
}

struct RecentView: View {
    @ObservedObject var library: LiveLibrary
    @State private var dateFilterKey = "all"

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    private var allSections: [DateSectionModel] {
        let grouped = Dictionary(grouping: library.items) {
            calendar.startOfDay(for: $0.modifiedAt)
        }
        return grouped.keys.sorted(by: >).map { date in
            DateSectionModel(date: date, items: (grouped[date] ?? []).sorted { $0.modifiedAt > $1.modifiedAt })
        }
    }

    private var displayedSections: [DateSectionModel] {
        guard dateFilterKey != "all" else { return allSections }
        return allSections.filter { dayKey($0.date) == dateFilterKey }
    }

    private var displayedItems: [LiveItem] { displayedSections.flatMap(\.items) }

    private var gridBounds: (CGFloat, CGFloat) {
        switch library.thumbnailDensity {
        case "compact": return (120, 155)
        case "large": return (175, 230)
        default: return (145, 190)
        }
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            ? "M月d日 EEEE"
            : "yyyy年M月d日 EEEE"
        return f.string(from: date)
    }

    private var filterTitle: String {
        if dateFilterKey == "all" { return "全部日期" }
        return allSections.first(where: { dayKey($0.date) == dateFilterKey }).map { dayTitle($0.date) } ?? "全部日期"
    }

    var body: some View {
        VStack(spacing: 0) {
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

                Button {
                    library.toggleSelection(for: displayedItems)
                } label: {
                    let allSelected = !displayedItems.isEmpty && Set(displayedItems.map(\.id)).isSubset(of: library.selected)
                    Label(allSelected ? "取消全选" : "全选", systemImage: "checkmark.circle")
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

            Divider()

            if displayedSections.isEmpty {
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
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
                        ForEach(displayedSections) { section in
                            Section {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: gridBounds.0, maximum: gridBounds.1), spacing: 12)],
                                    spacing: 14
                                ) {
                                    ForEach(section.items) { item in
                                        LiveCard(
                                            item: item,
                                            selected: library.selected.contains(item.id),
                                            showTechnicalInfo: library.showTechnicalInfo
                                        ) {
                                            let shift = NSEvent.modifierFlags.contains(.shift)
                                            library.toggle(item, orderedItems: displayedItems, extendRange: shift)
                                        }
                                        .contextMenu {
                                            Button("AirDrop 这一条") { library.airdrop([item]) }
                                            Button("在 Finder 中显示") { library.reveal(item) }
                                        }
                                    }
                                }
                                .padding(.horizontal, 26)
                            } header: {
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
                                        Label(selected ? "取消本日" : "选择本日", systemImage: selected ? "checkmark.circle.fill" : "checkmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 12.5, weight: .semibold))
                                }
                                .padding(.horizontal, 26)
                                .padding(.vertical, 11)
                                .background(.ultraThinMaterial)
                            }
                        }
                    }
                    .padding(.bottom, library.selected.isEmpty ? 28 : 102)
                }
            }

            if !library.selected.isEmpty {
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.accentColor).frame(width: 30, height: 30)
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
                    Button("清除选择") { library.selected.removeAll() }
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
        }
    }
}

struct HistoryView: View {
    @ObservedObject var library: LiveLibrary
    @State private var search = ""

    private var filtered: [LiveItem] {
        guard !search.isEmpty else { return library.items }
        return library.items.filter {
            $0.baseName.localizedCaseInsensitiveContains(search) ||
            $0.detailsText.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("处理历史")
                        .font(.system(size: 27, weight: .bold))
                    Text("所有已生成的 Live Photo，可重新投送或定位输出文件。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索文件名", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(26)

            Divider()

            List(filtered) { item in
                HStack(spacing: 14) {
                    ThumbnailView(url: item.imageURL)
                        .frame(width: 54, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.baseName)
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(item.detailsText + " · " + item.durationText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button("Finder") { library.reveal(item) }
                    Button {
                        library.airdrop([item])
                    } label: {
                        Label("AirDrop", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(.inset)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var library: LiveLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 27, weight: .bold))
                    Text("控制监听、文件位置和浏览体验。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                GroupBox("自动化") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("自动监听 DaVinci 输出目录", isOn: Binding(
                            get: { library.isMonitoring },
                            set: { library.setMonitoring($0) }
                        ))

                        Toggle("登录 Mac 后自动启动 SPP Live Export", isOn: Binding(
                            get: { library.launchAtLoginEnabled },
                            set: { library.setLaunchAtLogin($0) }
                        ))

                        Text("手动导入始终可用，不受自动监听开关影响。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                }

                GroupBox("文件夹") {
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("监听目录").font(.system(size: 13, weight: .semibold))
                                Text(library.inputURL.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("更改…") { library.chooseInputDirectory() }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("输出目录").font(.system(size: 13, weight: .semibold))
                                Text(library.outputURL.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("更改…") { library.chooseOutputDirectory() }
                        }
                    }
                    .padding(10)
                }

                GroupBox("浏览") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("缩略图密度")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { library.thumbnailDensity },
                                set: { library.setThumbnailDensity($0) }
                            )) {
                                Text("紧凑").tag("compact")
                                Text("标准").tag("standard")
                                Text("大").tag("large")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        Toggle("显示分辨率 / 编码 / 帧率", isOn: Binding(
                            get: { library.showTechnicalInfo },
                            set: { library.setShowTechnicalInfo($0) }
                        ))
                    }
                    .padding(10)
                }

                GroupBox("安全与缓存") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("原视频只读：不会移动、覆盖或删除 DaVinci / 手动导入的源文件。", systemImage: "lock.shield")
                        Label("AirDrop 临时 Live Photo Bundle 超过 24 小时会自动清理。", systemImage: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(10)
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

struct ContentView: View {
    @StateObject private var library = LiveLibrary()
    @State private var page: AppPage = .recent

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(library: library, page: $page)
            Divider()

            Group {
                switch page {
                case .recent:
                    RecentView(library: library)
                case .history:
                    HistoryView(library: library)
                case .settings:
                    SettingsView(library: library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.30))
        }
        .frame(minWidth: 1040, minHeight: 720)
        .animation(.easeInOut(duration: 0.15), value: page)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct SPPLiveExportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
