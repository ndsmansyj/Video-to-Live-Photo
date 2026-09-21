import SwiftUI
import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class LiveLibrary: ObservableObject {
    @Published var items: [LiveItem] = []
    @Published var selected: Set<String> = []
    @Published var isMonitoring: Bool
    @Published var isProcessing = false
    @Published var statusText = "准备中"
    @Published var inputURL: URL
    @Published var outputURL: URL
    @Published var launchAtLoginEnabled = false
    @Published var thumbnailDensity: ThumbnailDensity
    @Published var showTechnicalInfo: Bool

    var processedURL: URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent("Processed", isDirectory: true)
    }

    private var timer: Timer?
    private var observedSignatures: [String: String] = [:]
    private var failedSignatures: [String: String] = [:]
    private var activeInputs: Set<String> = []
    private var selectionAnchorID: String?
    private var mediaCache: [String: (fingerprint: String, info: MediaInfo)] = [:]

    init() {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Movies/SPP_Live_Export", isDirectory: true)

        inputURL = URL(
            fileURLWithPath: defaults.string(forKey: "inputPath")
                ?? root.appendingPathComponent("Input").path,
            isDirectory: true
        )
        outputURL = URL(
            fileURLWithPath: defaults.string(forKey: "outputPath")
                ?? root.appendingPathComponent("Output").path,
            isDirectory: true
        )
        isMonitoring = defaults.object(forKey: "monitoringEnabled") == nil
            ? true : defaults.bool(forKey: "monitoringEnabled")
        thumbnailDensity = ThumbnailDensity(
            rawValue: defaults.string(forKey: "thumbnailDensity") ?? ""
        ) ?? .standard
        showTechnicalInfo = defaults.object(forKey: "showTechnicalInfo") == nil
            ? true : defaults.bool(forKey: "showTechnicalInfo")

        if inputURL.standardizedFileURL == outputURL.standardizedFileURL {
            outputURL = root.appendingPathComponent("Output", isDirectory: true)
            defaults.set(outputURL.path, forKey: "outputPath")
        }

        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }

        prepareFolders()
        refresh()
        cleanupOldAirDropCache()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if self.isMonitoring { self.scanPendingInputs() }
            }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Library

    func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: outputURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let next = urls
            .filter { $0.pathExtension.lowercased() == "heic" }
            .compactMap { image -> LiveItem? in
                let stem = image.deletingPathExtension().lastPathComponent
                let movie = outputURL.appendingPathComponent(stem).appendingPathExtension("mov")
                guard fm.fileExists(atPath: movie.path) else { return nil }

                let modified = (try? image.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast

                let base = stem.replacingOccurrences(
                    of: #"_LIVE(?:_\d+)?$"#,
                    with: "",
                    options: .regularExpression
                )

                return LiveItem(
                    id: stem,
                    baseName: base,
                    imageURL: image,
                    videoURL: movie,
                    modifiedAt: modified,
                    media: mediaInfo(for: movie)
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        items = next
        let activeMedia = Set(next.map { $0.videoURL.path })
        mediaCache = mediaCache.filter { activeMedia.contains($0.key) }
        selected.formIntersection(Set(next.map(\.id)))
        statusText = isProcessing
            ? "正在生成 Live…"
            : (isMonitoring ? "正在监听 DaVinci" : "监听已暂停")
    }

    // MARK: - Selection

    func toggle(_ item: LiveItem, orderedItems: [LiveItem], extendRange: Bool = false) {
        if extendRange,
           let anchor = selectionAnchorID,
           let a = orderedItems.firstIndex(where: { $0.id == anchor }),
           let b = orderedItems.firstIndex(where: { $0.id == item.id }) {
            selected.formUnion(orderedItems[min(a, b)...max(a, b)].map(\.id))
        } else if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
        selectionAnchorID = item.id
    }

    func toggleSelection(for visibleItems: [LiveItem]) {
        toggleIDs(Set(visibleItems.map(\.id)))
    }

    func toggleGroup(_ groupItems: [LiveItem]) {
        toggleIDs(Set(groupItems.map(\.id)))
    }

    func isGroupSelected(_ groupItems: [LiveItem]) -> Bool {
        let ids = Set(groupItems.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selected)
    }

    var selectedItems: [LiveItem] {
        items.filter { selected.contains($0.id) }
    }

    private func toggleIDs(_ ids: Set<String>) {
        if !ids.isEmpty && ids.isSubset(of: selected) {
            selected.subtract(ids)
        } else {
            selected.formUnion(ids)
        }
    }

    // MARK: - AirDrop

    func airdropSelected() {
        airdrop(selectedItems)
    }

    func airdrop(_ picks: [LiveItem]) {
        guard !picks.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }

        do {
            cleanupOldAirDropCache()
            let packages = try makeLivePhotoPackages(picks)
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

    // MARK: - Import & watching

    func manualImport() {
        guard !isProcessing else {
            statusText = "正在处理，请稍后再导入"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "导入视频生成 Live Photo"
        panel.message = "可多选。原视频只读取，不移动、不修改。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]

        guard panel.runModal() == .OK else { return }
        let videos = panel.urls.filter(supportedVideo)
        guard !videos.isEmpty else { return }

        Task {
            for video in videos {
                let inWatchFolder =
                    video.deletingLastPathComponent().standardizedFileURL
                    == inputURL.standardizedFileURL
                await process(video, markProcessed: inWatchFolder)
            }
        }
    }

    private func scanPendingInputs() {
        guard !isProcessing else { return }

        let fm = FileManager.default
        let videos = ((try? fm.contentsOfDirectory(
            at: inputURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter(supportedVideo)
            .sorted { modificationDate($0) < modificationDate($1) }

        let currentPaths = Set(videos.map(\.path))
        observedSignatures = observedSignatures.filter { currentPaths.contains($0.key) }
        failedSignatures = failedSignatures.filter { currentPaths.contains($0.key) }

        for video in videos {
            let path = video.path
            guard !activeInputs.contains(path), !isMarkedProcessed(video) else { continue }

            let signature = fileFingerprint(video)
            guard !signature.isEmpty else { continue }
            if failedSignatures[path] == signature { continue }

            if observedSignatures[path] == signature {
                activeInputs.insert(path)
                Task { await process(video, markProcessed: true) }
                return
            }

            observedSignatures[path] = signature
        }
    }

    private func process(_ source: URL, markProcessed: Bool) async {
        let destination = outputURL
        isProcessing = true
        statusText = "正在生成 \(source.lastPathComponent)"

        defer {
            activeInputs.remove(source.path)
            observedSignatures.removeValue(forKey: source.path)
            isProcessing = false
            refresh()
        }

        guard let tool = bundledToolURL(),
              FileManager.default.isExecutableFile(atPath: tool.path) else {
            statusText = "转换器缺失"
            return
        }

        do {
            let result = try await runExporter(tool: tool, source: source, destination: destination)
            guard result.status == 0,
                  let line = result.output.split(separator: "\n")
                    .map(String.init)
                    .last(where: { $0.hasPrefix("OK\t") }) else {
                failedSignatures[source.path] = fileFingerprint(source)
                statusText = "转换失败：\(source.lastPathComponent)"
                return
            }

            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 4 else {
                failedSignatures[source.path] = fileFingerprint(source)
                statusText = "转换结果异常"
                return
            }

            failedSignatures.removeValue(forKey: source.path)
            if markProcessed {
                writeMarker(
                    source: source,
                    heic: parts[2],
                    mov: parts[3]
                )
            }
            statusText = "Live 已生成"
        } catch {
            failedSignatures[source.path] = fileFingerprint(source)
            statusText = "转换器启动失败：\(error.localizedDescription)"
        }
    }

    private func runExporter(
        tool: URL,
        source: URL,
        destination: URL
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            let pipe = Pipe()

            task.executableURL = tool
            task.arguments = [source.path, destination.path]
            task.standardOutput = pipe
            task.standardError = pipe
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (
                    process.terminationStatus,
                    String(decoding: data, as: UTF8.self)
                ))
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Settings

    func setMonitoring(_ enabled: Bool) {
        isMonitoring = enabled
        UserDefaults.standard.set(enabled, forKey: "monitoringEnabled")
        statusText = enabled ? "正在监听 DaVinci" : "监听已暂停"
    }

    func chooseInputDirectory() {
        guard let url = chooseDirectory(title: "选择 DaVinci 监听目录", current: inputURL) else { return }
        guard url.standardizedFileURL != outputURL.standardizedFileURL else {
            statusText = "监听目录不能和输出目录相同"
            return
        }

        inputURL = url
        observedSignatures.removeAll()
        failedSignatures.removeAll()
        UserDefaults.standard.set(url.path, forKey: "inputPath")
        prepareFolders()
    }

    func chooseOutputDirectory() {
        guard let url = chooseDirectory(title: "选择 Live Photo 输出目录", current: outputURL) else { return }
        guard url.standardizedFileURL != inputURL.standardizedFileURL else {
            statusText = "输出目录不能和监听目录相同"
            return
        }

        outputURL = url
        mediaCache.removeAll()
        UserDefaults.standard.set(url.path, forKey: "outputPath")
        prepareFolders()
        refresh()
    }

    func setThumbnailDensity(_ value: ThumbnailDensity) {
        thumbnailDensity = value
        UserDefaults.standard.set(value.rawValue, forKey: "thumbnailDensity")
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

    func revealInput() { NSWorkspace.shared.open(inputURL) }
    func revealOutput() { NSWorkspace.shared.open(outputURL) }
    func reveal(_ item: LiveItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.videoURL])
    }

    // MARK: - Files

    private func prepareFolders() {
        let fm = FileManager.default
        for directory in [inputURL, outputURL, processedURL] {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
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

    private func supportedVideo(_ url: URL) -> Bool {
        ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
    }

    private func bundledToolURL() -> URL? {
        Bundle.main.url(forResource: "spp-live-export", withExtension: nil)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func fileFingerprint(_ url: URL) -> String {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return "" }

        guard let size = values.fileSize, size > 0 else { return "" }
        return "\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private func markerURL(_ source: URL) -> URL {
        processedURL.appendingPathComponent(source.lastPathComponent + ".done")
    }

    private func isMarkedProcessed(_ source: URL) -> Bool {
        let marker = markerURL(source)
        guard FileManager.default.fileExists(atPath: marker.path),
              let text = try? String(contentsOf: marker, encoding: .utf8),
              text.contains("source=\(source.path)\n") else {
            return false
        }

        return modificationDate(marker) >= modificationDate(source)
    }

    private func writeMarker(source: URL, heic: String, mov: String) {
        let text = """
        source=\(source.path)
        source_fingerprint=\(fileFingerprint(source))
        processed_at=\(ISO8601DateFormatter().string(from: Date()))
        heic=\(heic)
        mov=\(mov)
        engine=SPP Live Export.app
        """
        try? text.write(to: markerURL(source), atomically: true, encoding: .utf8)
    }

    // MARK: - Media metadata

    private func mediaInfo(for url: URL) -> MediaInfo {
        let fingerprint = fileFingerprint(url)
        if let cached = mediaCache[url.path], cached.fingerprint == fingerprint {
            return cached.info
        }

        let info = probe(url)
        mediaCache[url.path] = (fingerprint, info)
        return info
    }

    private func probe(_ url: URL) -> MediaInfo {
        let ffprobe = ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe"]
            .first { FileManager.default.fileExists(atPath: $0) }

        guard let ffprobe else {
            return MediaInfo(durationText: "Live Photo", detailsText: "HEIC + MOV")
        }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: ffprobe)
        task.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,r_frame_rate:format=duration",
            "-of", "default=nw=1:nk=0",
            url.path
        ]
        task.standardOutput = pipe
        task.standardError = Pipe()

        guard (try? task.run()) != nil else {
            return MediaInfo(durationText: "Live Photo", detailsText: "HEIC + MOV")
        }
        task.waitUntilExit()

        let raw = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var fields: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }

        let seconds = Double(fields["duration"] ?? "") ?? 0
        let duration = seconds > 0 ? String(format: "%.2fs", seconds) : "Live Photo"
        let width = fields["width"] ?? ""
        let height = fields["height"] ?? ""
        let size = width.isEmpty || height.isEmpty ? "Live" : "\(width)×\(height)"
        let codec = (fields["codec_name"] ?? "").uppercased()
        let fps = friendlyFPS(fields["r_frame_rate"] ?? "")
        let details = [size, codec.isEmpty ? nil : codec, fps.isEmpty ? nil : "\(fps)fps"]
            .compactMap { $0 }
            .joined(separator: " · ")

        return MediaInfo(durationText: duration, detailsText: details)
    }

    private func friendlyFPS(_ raw: String) -> String {
        let values = raw.split(separator: "/").compactMap { Double($0) }
        guard values.count == 2, values[1] != 0 else { return raw }
        let fps = values[0] / values[1]
        return abs(fps.rounded() - fps) < 0.02
            ? String(Int(fps.rounded()))
            : String(format: "%.2f", fps)
    }

    // MARK: - Live Photo package

    private func makeLivePhotoPackages(_ picks: [LiveItem]) throws -> [URL] {
        let fm = FileManager.default
        let session = airDropCacheRoot()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: session, withIntermediateDirectories: true)

        return try picks.map { item in
            let package = session.appendingPathComponent(item.id).appendingPathExtension("pvt")
            try fm.createDirectory(at: package, withIntermediateDirectories: true)
            try fm.copyItem(
                at: item.imageURL,
                to: package.appendingPathComponent(item.id).appendingPathExtension("HEIC")
            )
            try fm.copyItem(
                at: item.videoURL,
                to: package.appendingPathComponent(item.id).appendingPathExtension("MOV")
            )
            try Self.livePhotoMetadata.write(
                to: package.appendingPathComponent("metadata.plist"),
                atomically: true,
                encoding: .utf8
            )
            return package
        }
    }

    private func airDropCacheRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Caches/com.songpanpan.SPPLiveExport/AirDrop",
                isDirectory: true
            )
    }

    private func cleanupOldAirDropCache() {
        let fm = FileManager.default
        let root = airDropCacheRoot()
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries where modificationDate(entry) < cutoff {
            try? fm.removeItem(at: entry)
        }
    }

    private static let livePhotoMetadata = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>PFVideoComplementMetadataVersionKey</key>
      <string>1</string>
    </dict>
    </plist>
    """
}
