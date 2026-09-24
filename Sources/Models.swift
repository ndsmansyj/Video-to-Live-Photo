import Foundation
import CoreGraphics

struct MediaInfo {
    let durationText: String
    let detailsText: String
}

struct LiveSourceMetadata: Codable {
    let sourcePath: String
    let coverSeconds: Double
    let clipStart: Double
    let clipDuration: Double
    let includeAudio: Bool?
    let generatedAt: Date
}

struct PendingVideo: Identifiable {
    let id: String
    let sourceURL: URL
    let baseName: String
    let sourceDuration: Double
    var coverSeconds: Double
    var clipStart: Double
    var clipDuration: Double

    init(
        sourceURL: URL,
        sourceDuration: Double,
        coverSeconds: Double? = nil,
        clipStart: Double? = nil,
        clipDuration: Double? = nil
    ) {
        self.id = sourceURL.standardizedFileURL.path
        self.sourceURL = sourceURL
        self.baseName = sourceURL.deletingPathExtension().lastPathComponent
        self.sourceDuration = sourceDuration

        let duration = min(max(min(0.5, sourceDuration), clipDuration ?? 3), sourceDuration)
        let defaultStart = sourceDuration <= duration
            ? 0
            : min(sourceDuration / 2, sourceDuration - duration)
        let start = min(
            max(0, clipStart ?? defaultStart),
            max(0, sourceDuration - duration)
        )
        let defaultCover = start
        let cover = min(
            max(start, coverSeconds ?? defaultCover),
            min(max(0, sourceDuration - 0.001), start + duration)
        )

        self.clipDuration = duration
        self.clipStart = start
        self.coverSeconds = cover
    }
}

struct LiveItem: Identifiable {
    let id: String
    let baseName: String
    let imageURL: URL
    let videoURL: URL
    let modifiedAt: Date
    let media: MediaInfo
    let sourceURL: URL?
    let coverSeconds: Double?
    let clipStart: Double?
    let clipDuration: Double?
    let includeAudio: Bool?

    var durationText: String { media.durationText }
    var detailsText: String { media.detailsText }
    var canEdit: Bool { sourceURL != nil }
}

struct DateSectionModel: Identifiable {
    let date: Date
    let items: [LiveItem]
    var id: Date { date }
}

enum AppPage: String, CaseIterable {
    case recent, history, settings, about
}

enum ThumbnailDensity: String, CaseIterable, Identifiable {
    case compact, standard, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "标准"
        case .large: "大"
        }
    }

    var gridRange: (CGFloat, CGFloat) {
        switch self {
        case .compact: (120, 155)
        case .standard: (145, 190)
        case .large: (175, 230)
        }
    }
}
