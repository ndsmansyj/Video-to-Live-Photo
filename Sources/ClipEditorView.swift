import SwiftUI
import AppKit
import AVKit
import AVFoundation

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

final class AdaptiveCoverTimelineNSView: NSView {
    var sourceDuration: Double = 1
    var clipStart: Double = 0
    var clipDuration: Double = 1
    var coverSeconds: Double = 0
    var onChange: ((Double, Double) -> Void)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 48)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let width = max(bounds.width, 1)
        let trackY: CGFloat = 7

        let base = NSBezierPath(
            roundedRect: NSRect(x: 0, y: trackY, width: width, height: 6),
            xRadius: 3,
            yRadius: 3
        )
        NSColor.secondaryLabelColor.withAlphaComponent(0.14).setFill()
        base.fill()

        let startX = x(for: clipStart)
        let endX = x(for: min(sourceDuration, clipStart + clipDuration))
        let range = NSBezierPath(
            roundedRect: NSRect(
                x: startX,
                y: trackY - 1,
                width: max(5, endX - startX),
                height: 8
            ),
            xRadius: 4,
            yRadius: 4
        )
        NSColor.controlAccentColor.withAlphaComponent(0.84).setFill()
        range.fill()

        let coverX = x(for: coverSeconds)
        NSColor.labelColor.withAlphaComponent(0.74).setFill()
        NSRect(x: coverX - 0.75, y: 0, width: 1.5, height: 21).fill()

        let badgeWidth: CGFloat = 48
        let badgeX = min(
            max(0, coverX - badgeWidth / 2),
            max(0, width - badgeWidth)
        )
        let badgeRect = NSRect(x: badgeX, y: 23, width: badgeWidth, height: 23)
        let badge = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: 6,
            yRadius: 6
        )
        NSColor.labelColor.withAlphaComponent(0.92).setFill()
        badge.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.windowBackgroundColor
        ]
        let text = NSString(string: "封面")
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: badgeRect.midX - size.width / 2,
                y: badgeRect.midY - size.height / 2
            ),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ratio = min(max(0, point.x / max(bounds.width, 1)), 1)
        let requestedCover = sourceDuration * Double(ratio)
        let duration = min(max(0.001, clipDuration), sourceDuration)
        let maxStart = max(0, sourceDuration - duration)

        var nextStart = min(max(0, clipStart), maxStart)
        let currentEnd = nextStart + duration

        if requestedCover < nextStart {
            nextStart = min(max(0, requestedCover), maxStart)
        } else if requestedCover > currentEnd {
            nextStart = min(max(0, requestedCover - duration), maxStart)
        }

        let nextCover = min(
            max(requestedCover, nextStart),
            min(sourceDuration, nextStart + duration)
        )

        clipStart = nextStart
        coverSeconds = nextCover
        needsDisplay = true
        onChange?(nextCover, nextStart)
    }

    private func x(for seconds: Double) -> CGFloat {
        guard sourceDuration > 0 else { return 0 }
        return CGFloat(min(max(0, seconds / sourceDuration), 1)) * bounds.width
    }
}

struct AdaptiveCoverTimeline: NSViewRepresentable {
    @Binding var coverSeconds: Double
    @Binding var clipStart: Double
    let sourceDuration: Double
    let clipDuration: Double

    func makeNSView(context: Context) -> AdaptiveCoverTimelineNSView {
        let view = AdaptiveCoverTimelineNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: AdaptiveCoverTimelineNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: AdaptiveCoverTimelineNSView) {
        view.sourceDuration = sourceDuration
        view.clipStart = clipStart
        view.clipDuration = clipDuration
        view.coverSeconds = coverSeconds
        view.onChange = { cover, start in
            DispatchQueue.main.async {
                self.coverSeconds = cover
                self.clipStart = start
            }
        }
        view.setAccessibilityLabel("封面")
        view.setAccessibilityValue(String(format: "%.2f 秒", coverSeconds))
        view.needsDisplay = true
    }
}

struct DurationStepper: NSViewRepresentable {
    @Binding var value: Double
    let minValue: Double
    let maxValue: Double
    let increment: Double

    final class Coordinator: NSObject {
        var parent: DurationStepper
        init(_ parent: DurationStepper) { self.parent = parent }

        @objc func changed(_ sender: NSStepper) {
            parent.value = sender.doubleValue
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStepper {
        let stepper = NSStepper(
            frame: .zero
        )
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.changed(_:))
        stepper.increment = increment
        stepper.autorepeat = true
        stepper.valueWraps = false
        stepper.controlSize = .small
        configure(stepper)
        return stepper
    }

    func updateNSView(_ stepper: NSStepper, context: Context) {
        context.coordinator.parent = self
        configure(stepper)
    }

    private func configure(_ stepper: NSStepper) {
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = increment
        stepper.doubleValue = min(max(value, minValue), maxValue)
    }
}

struct ClipEditorView: View {
    let sourceURL: URL
    let title: String
    let initialCoverSeconds: Double?
    let initialClipStart: Double?
    let initialClipDuration: Double?
    let actionTitle: String
    let onSave: (Double, Double, Double) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var durationFieldFocused: Bool

    @State private var player: AVPlayer
    @State private var sourceDuration: Double = 0
    @State private var sourceIsPortrait = false
    @State private var coverSeconds: Double = 0
    @State private var clipStart: Double = 0
    @State private var clipDuration: Double = 3
    @State private var durationText: String = "3"
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?

    init(
        sourceURL: URL,
        title: String,
        coverSeconds: Double? = nil,
        clipStart: Double? = nil,
        clipDuration: Double? = nil,
        actionTitle: String = "完成",
        onSave: @escaping (Double, Double, Double) async -> Bool
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.initialCoverSeconds = coverSeconds
        self.initialClipStart = clipStart
        self.initialClipDuration = clipDuration
        self.actionTitle = actionTitle
        self.onSave = onSave
        _player = State(initialValue: AVPlayer(url: sourceURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 10) {
                NativePlayerView(player: player)
                    .frame(height: previewHeight)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                if sourceDuration > 0 {
                    timeline

                    HStack {
                        Text("输出 \(timeText(clipStart)) – \(timeText(clipEnd))")
                        Spacer()
                        Text("封面 \(timeText(coverSeconds))")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                    durationControls
                    actionRow
                } else if let loadError {
                    Text(loadError)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    ProgressView("正在读取视频…")
                        .frame(maxWidth: .infinity, minHeight: 170)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(width: editorWidth, height: editorHeight)
        .task { await loadDuration() }
        .onChange(of: coverSeconds) { _ in
            player.pause()
            seekToCover()
        }
        .onChange(of: clipDuration) { newValue in
            normalizeAfterDurationChange(newValue)
        }
        .onChange(of: durationFieldFocused) { focused in
            if !focused { applyDurationText() }
        }
        .onDisappear { player.pause() }
    }

    private var visibleScreenSize: CGSize {
        if let size = NSApp.keyWindow?.screen?.visibleFrame.size {
            return size
        }
        if let size = NSScreen.main?.visibleFrame.size {
            return size
        }
        return CGSize(width: 1440, height: 900)
    }

    private var editorWidth: CGFloat {
        if sourceIsPortrait {
            return min(800, max(720, visibleScreenSize.width - 700))
        }
        return min(920, max(820, visibleScreenSize.width - 420))
    }

    private var editorHeight: CGFloat {
        if sourceIsPortrait {
            return min(700, max(620, visibleScreenSize.height - 180))
        }
        return min(640, max(560, visibleScreenSize.height - 180))
    }

    private var previewHeight: CGFloat {
        if sourceIsPortrait {
            return min(430, max(340, editorHeight - 270))
        }
        return min(380, max(285, editorHeight - 275))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("选择片段与封面")
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }

    private var timeline: some View {
        VStack(spacing: 3) {
            AdaptiveCoverTimeline(
                coverSeconds: $coverSeconds,
                clipStart: $clipStart,
                sourceDuration: sourceDuration,
                clipDuration: effectiveDuration
            )
            .frame(height: 48)

            HStack {
                Text(timeText(0))
                Spacer()
                Text(timeText(sourceDuration))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
    }

    private var durationControls: some View {
        HStack(spacing: 7) {
            Text("时长")
                .font(.system(size: 12.5, weight: .medium))

            TextField("", text: $durationText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .focused($durationFieldFocused)
                .onSubmit { applyDurationText() }

            DurationStepper(
                value: Binding(
                    get: { effectiveDuration },
                    set: {
                        clipDuration = $0
                        durationText = Self.numberText($0)
                    }
                ),
                minValue: minimumDuration,
                maxValue: max(minimumDuration, sourceDuration),
                increment: 0.5
            )
            .frame(width: 18, height: 23)

            Text("秒")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider().frame(height: 20).padding(.horizontal, 2)

            quickDurationButton(3, title: "3 秒")
            quickDurationButton(5, title: "5 秒")
            quickDurationButton(10, title: "10 秒")
            Button("原片") { setClipDuration(sourceDuration) }
                .controlSize(.small)
                .foregroundStyle(isFullLength ? Color.accentColor : Color.primary)

            Spacer()

            Text("朋友圈仅支持 3 秒 Live")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                previewFinalRange()
            } label: {
                Label("播放片段", systemImage: "play.fill")
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(isSaving ? "正在保存…" : actionTitle) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(sourceDuration <= 0 || isSaving)
        }
    }

    private func quickDurationButton(_ seconds: Double, title: String) -> some View {
        Button(title) { setClipDuration(seconds) }
            .controlSize(.small)
            .foregroundStyle(isDuration(seconds) ? Color.accentColor : Color.primary)
            .disabled(sourceDuration > 0 && seconds > sourceDuration + 0.02)
    }

    private var minimumDuration: Double {
        guard sourceDuration > 0 else { return 0.5 }
        return min(0.5, sourceDuration)
    }

    private var effectiveDuration: Double {
        guard sourceDuration > 0 else { return max(0.5, clipDuration) }
        return min(max(minimumDuration, clipDuration), sourceDuration)
    }

    private var clipEnd: Double {
        min(sourceDuration, clipStart + effectiveDuration)
    }

    private var isFullLength: Bool {
        sourceDuration > 0 && abs(effectiveDuration - sourceDuration) < 0.02
    }

    private func isDuration(_ seconds: Double) -> Bool {
        guard sourceDuration > 0 else { return false }
        return abs(effectiveDuration - min(seconds, sourceDuration)) < 0.02 && !isFullLength
    }

    private func loadDuration() async {
        do {
            let asset = AVURLAsset(url: sourceURL)
            let loaded = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(loaded)
            guard seconds.isFinite, seconds > 0 else {
                loadError = "无法读取视频时长。"
                return
            }

            sourceDuration = seconds

            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let displayRect = CGRect(origin: .zero, size: naturalSize)
                    .applying(transform)
                    .standardized
                sourceIsPortrait = displayRect.height > displayRect.width
            }

            let duration = min(
                max(min(0.5, seconds), initialClipDuration ?? 3),
                seconds
            )
            clipDuration = duration
            durationText = Self.numberText(duration)

            let maxStart = max(0, seconds - duration)
            let defaultStart = seconds <= duration
                ? 0
                : min(seconds / 2, maxStart)
            clipStart = min(max(0, initialClipStart ?? defaultStart), maxStart)

            let defaultCover = clipStart
            coverSeconds = min(
                max(initialCoverSeconds ?? defaultCover, clipStart),
                clipEnd
            )
            seekToCover()
        } catch {
            loadError = "无法读取原视频。"
        }
    }

    private func normalizeAfterDurationChange(_ newValue: Double) {
        guard sourceDuration > 0 else { return }

        let duration = min(max(minimumDuration, newValue), sourceDuration)
        if abs(duration - clipDuration) > 0.0001 {
            clipDuration = duration
        }
        durationText = Self.numberText(duration)

        let maxStart = max(0, sourceDuration - duration)
        var start = min(max(0, clipStart), maxStart)

        if coverSeconds < start {
            start = min(max(0, coverSeconds), maxStart)
        } else if coverSeconds > start + duration {
            start = min(max(0, coverSeconds - duration), maxStart)
        }

        clipStart = start
        coverSeconds = min(max(coverSeconds, start), start + duration)
    }

    private func setClipDuration(_ seconds: Double) {
        clipDuration = min(max(minimumDuration, seconds), sourceDuration)
        durationText = Self.numberText(clipDuration)
        durationFieldFocused = false
    }

    private func applyDurationText() {
        let normalized = durationText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            durationText = Self.numberText(effectiveDuration)
            return
        }
        setClipDuration(value)
    }

    private func previewFinalRange() {
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = CMTime(
            seconds: clipEnd,
            preferredTimescale: 600
        )
        player.seek(
            to: CMTime(seconds: clipStart, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player.play()
    }

    private func seekToCover() {
        player.currentItem?.forwardPlaybackEndTime = .invalid
        player.seek(
            to: CMTime(seconds: coverSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func save() {
        applyDurationText()
        isSaving = true
        saveError = nil
        player.pause()

        Task {
            let ok = await onSave(coverSeconds, clipStart, effectiveDuration)
            isSaving = false
            if ok { dismiss() }
            else { saveError = "无法保存。" }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let safe = max(0, seconds)
        let minutes = Int(safe) / 60
        let remainder = safe - Double(minutes * 60)
        if minutes > 0 { return String(format: "%d:%04.1f", minutes, remainder) }
        return String(format: "%.1f 秒", remainder)
    }

    private static func numberText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.02 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
