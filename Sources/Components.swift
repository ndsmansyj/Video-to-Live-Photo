import SwiftUI
import AppKit
import ImageIO
import AVFoundation

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 240
    }

    func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640
                ] as CFDictionary
              ) else { return nil }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(image, forKey: key)
        return image
    }

    func remove(for url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}

struct ThumbnailView: View {
    let url: URL

    var body: some View {
        ZStack {
            Color.primary.opacity(0.035)

            if let image = ThumbnailCache.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "livephoto")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
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
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: item.imageURL)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                selectionBadge
                    .padding(9)

                VStack {
                    Spacer()
                    HStack {
                        Label(item.durationText, systemImage: "livephoto")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.50), in: Capsule())
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
                    .help(item.baseName)

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

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.accentColor : Color.black.opacity(0.28))
                .frame(width: 26, height: 26)
            Image(systemName: selected ? "checkmark" : "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}



struct VideoSourceThumbnailView: View {
    let url: URL
    let time: Double

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.035)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(url.path)|\(String(format: "%.3f", time))") {
            image = await makeThumbnail()
        }
    }

    private func makeThumbnail() async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 560, height: 560)

        do {
            let (cg, _) = try await generator.image(
                at: CMTime(seconds: max(0, time), preferredTimescale: 600)
            )
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
}

struct PendingVideoCard: View {
    let item: PendingVideo
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Button(action: onEdit) {
                    VideoSourceThumbnailView(
                        url: item.sourceURL,
                        time: item.coverSeconds
                    )
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("调整片段与封面")

                overlayButton(
                    icon: "xmark",
                    help: "移除",
                    action: onRemove
                )
                .padding(9)

                VStack {
                    Spacer()
                    HStack {
                        Label(durationText(item.clipDuration), systemImage: "clock")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.50), in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(9)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.baseName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .help(item.baseName)

                Text(
                    "片段 \(timeText(item.clipStart))–\(timeText(item.clipStart + item.clipDuration)) · 封面 \(timeText(item.coverSeconds))"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func overlayButton(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func durationText(_ seconds: Double) -> String {
        if abs(seconds.rounded() - seconds) < 0.02 {
            return "\(Int(seconds.rounded())) 秒"
        }
        return String(format: "%.1f 秒", seconds)
    }

    private func timeText(_ seconds: Double) -> String {
        if seconds >= 60 {
            return String(
                format: "%d:%04.1f",
                Int(seconds) / 60,
                seconds.truncatingRemainder(dividingBy: 60)
            )
        }
        return String(format: "%.1f", seconds)
    }
}

struct BatchSoundToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text("声音")
                .font(.system(size: 12.5, weight: .medium))

            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isOn.toggle()
                }
            } label: {
                ZStack {
                    Capsule()
                        .fill(isOn ? Color.green : Color.red)
                        .frame(width: 46, height: 24)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 1, y: 0.5)
                        .offset(x: isOn ? 10 : -10)
                }
            }
            .buttonStyle(.plain)
            .help(isOn ? "保留视频声音" : "静音生成")
            .accessibilityLabel("声音")
            .accessibilityValue(isOn ? "开启" : "关闭")

            Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.green : Color.red)
                .frame(width: 14)
        }
    }
}

struct Sidebar: View {
    @ObservedObject var library: LiveLibrary
    @Binding var page: AppPage

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)

                Text("Video to Live Turbo")
                    .font(.system(size: 15.5, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)

            VStack(spacing: 5) {
                nav(.recent, "首页", "house.fill")
                nav(.settings, "设置", "slider.horizontal.3")
                nav(.about, "关于", "info.circle")
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(library.isMonitoring ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)
                    Text(library.statusText)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                }

                if !library.failedSources.isEmpty, let message = library.operationMessage {
                    Divider()

                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Button("重试失败项") {
                        library.retryFailed()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
                }

                Button("打开输出文件夹") {
                    library.revealOutput()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
            .padding(13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(20)
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    private func nav(_ target: AppPage, _ title: String, _ icon: String) -> some View {
        Button {
            page = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 14, weight: page == target ? .semibold : .regular))
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                page == target ? Color.primary.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(page == target ? .primary : .secondary)
        .contentShape(Rectangle())
    }
}
