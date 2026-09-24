import SwiftUI
import AppKit
import Foundation
import AVFoundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class LiveLibrary: ObservableObject {
    @Published var items: [LiveItem] = []
    @Published var pendingVideos: [PendingVideo] = []
    @Published var selected: Set<String> = []
    @Published var isMonitoring: Bool
    @Published var isProcessing = false
    @Published var statusText = "准备中"
    @Published var inputURL: URL
    @Published var outputURL: URL
    @Published var launchAtLoginEnabled = false
    @Published var thumbnailDensity: ThumbnailDensity
    @Published var thumbnailZoom: Double
    @Published var showTechnicalInfo: Bool
    @Published var manualIncludeAudio = true
    @Published private var sessionGeneratedIDs: Set<String> = []
    @Published var operationMessage: String?
    @Published var failedSources: [URL] = []

    var processedURL: URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent("Processed", isDirectory: true)
    }

    var sessionItems: [LiveItem] {
        items.filter { sessionGeneratedIDs.contains($0.id) }
    }

    var thumbnailColumnCount: Int {
        let clamped = min(max(thumbnailZoom, 0), 1)
        return Int(round(7 - clamped * 4))
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
            ? false : defaults.bool(forKey: "monitoringEnabled")
        thumbnailDensity = ThumbnailDensity(
            rawValue: defaults.string(forKey: "thumbnailDensity") ?? ""
        ) ?? .standard
        thumbnailZoom = defaults.object(forKey: "thumbnailZoom") == nil
            ? 0.25 : defaults.double(forKey: "thumbnailZoom")
        showTechnicalInfo = defaults.object(forKey: "showTechnicalInfo") == nil
            ? false : defaults.bool(forKey: "showTechnicalInfo")

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
        if isMonitoring { scanPendingInputs() }

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

                let source = sourceMetadata(for: stem)
                let sourceURL = source.map { URL(fileURLWithPath: $0.sourcePath) }
                    .flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }

                return LiveItem(
                    id: stem,
                    baseName: base,
                    imageURL: image,
                    videoURL: movie,
                    modifiedAt: modified,
                    media: mediaInfo(for: movie),
                    sourceURL: sourceURL,
                    coverSeconds: source?.coverSeconds,
                    clipStart: source?.clipStart,
                    clipDuration: source?.clipDuration,
                    includeAudio: source?.includeAudio
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        items = next
        let activeMedia = Set(next.map { $0.videoURL.path })
        mediaCache = mediaCache.filter { activeMedia.contains($0.key) }
        selected.formIntersection(Set(next.map(\.id)))
        statusText = isProcessing
            ? "正在生成 Live Photo…"
            : (isMonitoring ? "文件夹自动转换中" : "就绪")
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

    func clearSelection() {
        selected.removeAll()
        selectionAnchorID = nil
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
        guard !picks.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            operationMessage = "AirDrop 当前不可用。"
            return
        }

        do {
            cleanupOldAirDropCache()
            let packages = try makeLivePhotoPackages(picks)
            guard service.canPerform(withItems: packages) else {
                operationMessage = "无法准备 AirDrop 文件，请重试。"
                return
            }
            operationMessage = nil
            service.perform(withItems: packages)
        } catch {
            operationMessage = "无法准备 AirDrop 文件，请重试。"
        }
    }

    // MARK: - Import & watching

    func manualImport() {
        guard !isProcessing else {
            statusText = "正在处理，请稍后再导入"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "导入视频"
        panel.message = "导入后可先选择片段、封面和时长，再手动生成。原视频只读取，不移动、不修改。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]

        guard panel.runModal() == .OK else { return }
        importVideos(panel.urls)
    }

    func importVideos(_ urls: [URL]) {
        guard !isProcessing else {
            operationMessage = "正在处理，请稍后再导入。"
            return
        }

        let existing = Set(pendingVideos.map { $0.sourceURL.standardizedFileURL.path })
        let videos = urls
            .filter(supportedVideo)
            .filter { !existing.contains($0.standardizedFileURL.path) }

        guard !videos.isEmpty else {
            operationMessage = "没有新的可导入视频。"
            return
        }

        Task {
            var added = 0
            var failed: [String] = []

            for video in videos {
                do {
                    let asset = AVURLAsset(url: video)
                    let loaded = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(loaded)
                    guard seconds.isFinite, seconds > 0 else {
                        failed.append(video.lastPathComponent)
                        continue
                    }

                    pendingVideos.append(
                        PendingVideo(
                            sourceURL: video,
                            sourceDuration: seconds
                        )
                    )
                    added += 1
                } catch {
                    failed.append(video.lastPathComponent)
                }
            }

            if failed.isEmpty {
                operationMessage = added == 1
                    ? "已加入待生成，可先调整封面和时长。"
                    : "已加入 \(added) 个待生成视频。"
            } else {
                operationMessage = "已加入 \(added) 个，\(failed.count) 个无法读取。"
            }
        }
    }

    func updatePending(
        id: String,
        coverSeconds: Double,
        clipStart: Double,
        clipDuration: Double
    ) {
        guard let index = pendingVideos.firstIndex(where: { $0.id == id }) else { return }
        let current = pendingVideos[index]
        pendingVideos[index] = PendingVideo(
            sourceURL: current.sourceURL,
            sourceDuration: current.sourceDuration,
            coverSeconds: coverSeconds,
            clipStart: clipStart,
            clipDuration: clipDuration
        )
    }

    func removePending(_ id: String) {
        pendingVideos.removeAll { $0.id == id }
    }

    func generatePending() {
        guard !isProcessing, !pendingVideos.isEmpty else { return }
        let batch = pendingVideos

        Task {
            var successIDs: Set<String> = []
            var failures: [URL] = []

            for pending in batch {
                let inWatchFolder =
                    pending.sourceURL.deletingLastPathComponent().standardizedFileURL
                    == inputURL.standardizedFileURL

                let ok = await process(
                    pending.sourceURL,
                    markProcessed: inWatchFolder,
                    coverSeconds: pending.coverSeconds,
                    clipStart: pending.clipStart,
                    clipDuration: pending.clipDuration,
                    includeAudio: manualIncludeAudio
                )
                if ok {
                    successIDs.insert(pending.id)
                } else {
                    failures.append(pending.sourceURL)
                }
            }

            pendingVideos.removeAll { successIDs.contains($0.id) }
            failedSources = failures

            let success = successIDs.count
            if failures.isEmpty {
                operationMessage = success == 1
                    ? "Live Photo 已生成。"
                    : "已生成 \(success) 个 Live Photo。"
            } else {
                operationMessage = "已生成 \(success) 个，失败 \(failures.count) 个。"
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
            let stagedManually = pendingVideos.contains {
                $0.sourceURL.standardizedFileURL.path == video.standardizedFileURL.path
            }
            guard !activeInputs.contains(path),
                  !isMarkedProcessed(video),
                  !stagedManually else { continue }

            let signature = fileFingerprint(video)
            guard !signature.isEmpty else { continue }
            if failedSignatures[path] == signature { continue }

            if observedSignatures[path] == signature {
                activeInputs.insert(path)
                Task { _ = await process(video, markProcessed: true) }
                return
            }

            observedSignatures[path] = signature
        }
    }

    @discardableResult
    private func process(
        _ source: URL,
        markProcessed: Bool,
        coverSeconds: Double? = nil,
        clipStart: Double? = nil,
        clipDuration: Double? = nil,
        includeAudio: Bool = true
    ) async -> Bool {
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
            operationMessage = "转换器缺失，无法生成 Live Photo。"
            failedSources = [source]
            return false
        }

        do {
            let result = try await runExporter(
                tool: tool,
                source: source,
                destination: destination,
                coverSeconds: coverSeconds,
                clipStart: clipStart,
                clipDuration: clipDuration,
                includeAudio: includeAudio
            )
            guard result.status == 0,
                  let info = parseExporterOutput(result.output) else {
                failedSignatures[source.path] = fileFingerprint(source)
                failedSources = [source]
                operationMessage = "转换失败：\(source.lastPathComponent)"
                return false
            }

            failedSignatures.removeValue(forKey: source.path)
            if markProcessed {
                writeMarker(source: source, heic: info.heic, mov: info.mov)
            }
            let stem = URL(fileURLWithPath: info.heic).deletingPathExtension().lastPathComponent
            writeSourceMetadata(
                stem: stem,
                source: source,
                coverSeconds: info.coverSeconds,
                clipStart: info.clipStart,
                clipDuration: info.clipDuration,
                includeAudio: includeAudio
            )
            sessionGeneratedIDs.insert(stem)
            return true
        } catch {
            failedSignatures[source.path] = fileFingerprint(source)
            failedSources = [source]
            operationMessage = "转换失败：\(source.lastPathComponent)"
            return false
        }
    }

    private struct ExporterInfo {
        let heic: String
        let mov: String
        let coverSeconds: Double
        let clipStart: Double
        let clipDuration: Double
    }

    private func parseExporterOutput(_ output: String) -> ExporterInfo? {
        guard let line = output.split(separator: "\n")
            .map(String.init)
            .last(where: { $0.hasPrefix("OK\t") }) else { return nil }
        let parts = line.split(separator: "\t").map(String.init)
        guard parts.count >= 7,
              let cover = Double(parts[4]),
              let start = Double(parts[5]),
              let duration = Double(parts[6]) else { return nil }
        return ExporterInfo(
            heic: parts[2],
            mov: parts[3],
            coverSeconds: cover,
            clipStart: start,
            clipDuration: duration
        )
    }

    private func runExporter(
        tool: URL,
        source: URL,
        destination: URL,
        coverSeconds: Double? = nil,
        clipStart: Double? = nil,
        clipDuration: Double? = nil,
        includeAudio: Bool = true,
        preferredStem: String? = nil
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            let pipe = Pipe()

            task.executableURL = tool
            var arguments: [String] = []
            if let coverSeconds {
                arguments += ["--cover", String(format: "%.6f", coverSeconds)]
            }
            if let clipStart {
                arguments += ["--start", String(format: "%.6f", clipStart)]
            }
            if let clipDuration {
                arguments += ["--duration", String(format: "%.6f", clipDuration)]
            }
            if !includeAudio {
                arguments += ["--mute"]
            }
            if let preferredStem {
                arguments += ["--stem", preferredStem]
            }
            arguments += [source.path, destination.path]
            task.arguments = arguments
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

    func retryFailed() {
        let pending = failedSources
        guard !pending.isEmpty else { return }
        failedSources = []
        operationMessage = nil

        Task {
            var success = 0
            var failures: [URL] = []
            for source in pending where FileManager.default.fileExists(atPath: source.path) {
                let inWatchFolder =
                    source.deletingLastPathComponent().standardizedFileURL
                    == inputURL.standardizedFileURL
                if await process(source, markProcessed: inWatchFolder) {
                    success += 1
                } else {
                    failures.append(source)
                }
            }
            failedSources = failures
            operationMessage = failures.isEmpty
                ? "重试完成，已生成 \(success) 个 Live Photo。"
                : "重试完成 \(success) 个，仍失败 \(failures.count) 个。"
        }
    }

    func regenerate(
        _ item: LiveItem,
        coverSeconds: Double,
        clipStart: Double,
        clipDuration: Double
    ) async -> Bool {
        guard let source = item.sourceURL,
              FileManager.default.fileExists(atPath: source.path) else {
            operationMessage = "原视频不可用，无法调整封面。"
            return false
        }
        guard let tool = bundledToolURL() else {
            operationMessage = "转换器缺失，无法调整封面。"
            return false
        }

        isProcessing = true
        statusText = "正在更新 \(item.baseName)"
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
            .appendingPathComponent("Video to Live Turbo Edit-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: temp)
            isProcessing = false
            refresh()
        }

        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            let result = try await runExporter(
                tool: tool,
                source: source,
                destination: temp,
                coverSeconds: coverSeconds,
                clipStart: clipStart,
                clipDuration: clipDuration,
                includeAudio: item.includeAudio ?? true,
                preferredStem: item.id
            )
            guard result.status == 0, let info = parseExporterOutput(result.output) else {
                operationMessage = "调整失败，原结果已保留。"
                return false
            }

            let newImage = temp.appendingPathComponent(info.heic)
            let newVideo = temp.appendingPathComponent(info.mov)
            let backupImage = temp.appendingPathComponent("backup.heic")
            let backupVideo = temp.appendingPathComponent("backup.mov")
            let originalImageDate = modificationDate(item.imageURL)
            let originalVideoDate = modificationDate(item.videoURL)
            try fm.copyItem(at: item.imageURL, to: backupImage)
            try fm.copyItem(at: item.videoURL, to: backupVideo)

            do {
                try fm.removeItem(at: item.imageURL)
                try fm.copyItem(at: newImage, to: item.imageURL)
                try fm.removeItem(at: item.videoURL)
                try fm.copyItem(at: newVideo, to: item.videoURL)
                try? fm.setAttributes([.modificationDate: originalImageDate], ofItemAtPath: item.imageURL.path)
                try? fm.setAttributes([.modificationDate: originalVideoDate], ofItemAtPath: item.videoURL.path)
            } catch {
                try? fm.removeItem(at: item.imageURL)
                try? fm.removeItem(at: item.videoURL)
                try? fm.copyItem(at: backupImage, to: item.imageURL)
                try? fm.copyItem(at: backupVideo, to: item.videoURL)
                throw error
            }

            writeSourceMetadata(
                stem: item.id,
                source: source,
                coverSeconds: info.coverSeconds,
                clipStart: info.clipStart,
                clipDuration: info.clipDuration,
                includeAudio: item.includeAudio ?? true
            )
            mediaCache.removeValue(forKey: item.videoURL.path)
            ThumbnailCache.shared.remove(for: item.imageURL)
            operationMessage = "封面已更新。"
            return true
        } catch {
            operationMessage = "调整失败，原结果已保留。"
            return false
        }
    }

    // MARK: - Settings

    func setMonitoring(_ enabled: Bool) {
        isMonitoring = enabled
        UserDefaults.standard.set(enabled, forKey: "monitoringEnabled")
        statusText = enabled ? "文件夹自动转换中" : "就绪"
        if enabled { scanPendingInputs() }
    }

    func chooseInputDirectory() {
        guard let url = chooseDirectory(title: "选择自动转换文件夹", current: inputURL) else { return }
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

    func setThumbnailZoom(_ value: Double) {
        thumbnailZoom = min(max(value, 0), 1)
        UserDefaults.standard.set(thumbnailZoom, forKey: "thumbnailZoom")
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
        engine=Video to Live Turbo
        """
        try? text.write(to: markerURL(source), atomically: true, encoding: .utf8)
    }


    private func sourceMetadataURL(for stem: String) -> URL {
        processedURL.appendingPathComponent(stem + ".source.json")
    }

    private func sourceMetadata(for stem: String) -> LiveSourceMetadata? {
        let url = sourceMetadataURL(for: stem)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LiveSourceMetadata.self, from: data)
    }

    private func writeSourceMetadata(
        stem: String,
        source: URL,
        coverSeconds: Double,
        clipStart: Double,
        clipDuration: Double,
        includeAudio: Bool
    ) {
        let metadata = LiveSourceMetadata(
            sourcePath: source.path,
            coverSeconds: coverSeconds,
            clipStart: clipStart,
            clipDuration: clipDuration,
            includeAudio: includeAudio,
            generatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: sourceMetadataURL(for: stem), options: .atomic)
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
        let duration: String
        if seconds <= 0 {
            duration = "Live Photo"
        } else if abs(seconds.rounded() - seconds) < 0.02 {
            duration = "\(Int(seconds.rounded())) 秒"
        } else {
            duration = String(format: "%.1f 秒", seconds)
        }
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
