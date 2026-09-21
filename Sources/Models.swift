import Foundation
import CoreGraphics

struct MediaInfo {
    let durationText: String
    let detailsText: String
}

struct LiveItem: Identifiable {
    let id: String
    let baseName: String
    let imageURL: URL
    let videoURL: URL
    let modifiedAt: Date
    let media: MediaInfo

    var durationText: String { media.durationText }
    var detailsText: String { media.detailsText }
}

struct DateSectionModel: Identifiable {
    let date: Date
    let items: [LiveItem]
    var id: Date { date }
}

enum AppPage: String, CaseIterable {
    case recent, history, settings
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
