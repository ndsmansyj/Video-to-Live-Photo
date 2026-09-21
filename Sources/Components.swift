import SwiftUI
import AppKit
import ImageIO

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
}

struct ThumbnailView: View {
    let url: URL

    var body: some View {
        if let image = ThumbnailCache.shared.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.82), .gray.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "livephoto")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
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

                    selectionBadge
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

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.accentColor : Color.black.opacity(0.34))
                .frame(width: 27, height: 27)
            Image(systemName: selected ? "checkmark" : "circle")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct Sidebar: View {
    @ObservedObject var library: LiveLibrary
    @Binding var page: AppPage

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SPP")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Live Export")
                    .font(.system(size: 22, weight: .bold))
            }

            VStack(spacing: 3) {
                nav(.recent, "最近生成", "rectangle.stack.fill")
                nav(.history, "处理历史", "clock.arrow.circlepath")
                nav(.settings, "设置", "slider.horizontal.3")
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

                Text(shortPath(library.inputURL))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button("输入目录") { library.revealInput() }
                    Button("输出目录") { library.revealOutput() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    private func nav(_ target: AppPage, _ title: String, _ icon: String) -> some View {
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

    private func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
