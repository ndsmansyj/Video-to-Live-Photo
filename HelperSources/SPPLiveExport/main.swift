import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum LiveError: Error, CustomStringConvertible {
    case noVideoTrack
    case invalidDuration
    case imageDestination
    case imageWrite
    case exportSession
    case exportFailed(String)

    var description: String {
        switch self {
        case .noVideoTrack: return "No video track found"
        case .invalidDuration: return "Invalid video duration"
        case .imageDestination: return "Could not create HEIC destination"
        case .imageWrite: return "Could not write HEIC image"
        case .exportSession: return "Could not create passthrough export session"
        case .exportFailed(let s): return "MOV export failed: \(s)"
        }
    }
}

struct ExportResult {
    let imageURL: URL
    let videoURL: URL
    let coverSeconds: Double
    let clipStart: Double
    let clipDuration: Double
}

struct LivePhotoExporter {
    static let targetDuration = 3.0

    func export(
        input: URL,
        outputDirectory: URL,
        requestedCoverSeconds: Double? = nil,
        requestedStartSeconds: Double? = nil,
        requestedDuration: Double? = nil,
        includeAudio: Bool = true,
        preferredStem: String? = nil
    ) async throws -> ExportResult {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { throw LiveError.invalidDuration }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw LiveError.noVideoTrack }

        let safeMaxCover = max(0, seconds - 0.001)
        let requestedClipDuration = requestedDuration ?? Self.targetDuration
        let clipDuration = min(max(min(0.5, seconds), requestedClipDuration), seconds)

        let defaultStart = seconds <= clipDuration
            ? 0
            : min(seconds / 2.0, seconds - clipDuration)

        let clipStart: Double
        if seconds <= clipDuration {
            clipStart = 0
        } else if let requestedStartSeconds {
            clipStart = min(max(0, requestedStartSeconds), seconds - clipDuration)
        } else {
            clipStart = defaultStart
        }

        let requestedCover = requestedCoverSeconds ?? clipStart
        let clampedCoverSeconds = min(
            max(requestedCover, clipStart),
            min(safeMaxCover, clipStart + clipDuration)
        )
        let coverOffset = max(0, clampedCoverSeconds - clipStart)

        let coverTime = CMTime(seconds: clampedCoverSeconds, preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if #available(macOS 15.0, *) {
            generator.dynamicRangePolicy = .matchSource
        }
        let (coverImage, _) = try await generator.image(at: coverTime)

        let uuid = UUID().uuidString
        let safeBase = input.deletingPathExtension().lastPathComponent
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fm = FileManager.default
        var stem = preferredStem ?? "\(safeBase)_LIVE"
        if preferredStem == nil {
            var index = 2
            while fm.fileExists(atPath: outputDirectory.appendingPathComponent(stem + ".heic").path)
               || fm.fileExists(atPath: outputDirectory.appendingPathComponent(stem + ".mov").path) {
                stem = "\(safeBase)_LIVE_\(index)"
                index += 1
            }
        }

        let imageURL = outputDirectory.appendingPathComponent(stem + ".heic")
        let videoURL = outputDirectory.appendingPathComponent(stem + ".mov")

        do {
            try writeHEIC(image: coverImage, uuid: uuid, to: imageURL)
            try await writeMOV(
                asset: asset,
                uuid: uuid,
                clipStart: clipStart,
                clipDuration: clipDuration,
                coverOffset: coverOffset,
                includeAudio: includeAudio,
                to: videoURL
            )
            return ExportResult(
                imageURL: imageURL,
                videoURL: videoURL,
                coverSeconds: clampedCoverSeconds,
                clipStart: clipStart,
                clipDuration: clipDuration
            )
        } catch {
            try? fm.removeItem(at: imageURL)
            try? fm.removeItem(at: videoURL)
            throw error
        }
    }

    private func writeHEIC(image: CGImage, uuid: String, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else { throw LiveError.imageDestination }

        let maker: [String: Any] = ["17": uuid]
        let props: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: maker,
            kCGImageDestinationOptimizeColorForSharing: false
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw LiveError.imageWrite }
    }

    private func writeMOV(
        asset: AVAsset,
        uuid: String,
        clipStart: Double,
        clipDuration: Double,
        coverOffset: Double,
        includeAudio: Bool,
        to url: URL
    ) async throws {
        let exportAsset: AVAsset
        if includeAudio {
            exportAsset = asset
        } else {
            let composition = AVMutableComposition()
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            for sourceTrack in videoTracks {
                guard let targetTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }

                let sourceRange = try await sourceTrack.load(.timeRange)
                try targetTrack.insertTimeRange(
                    sourceRange,
                    of: sourceTrack,
                    at: sourceRange.start
                )
                targetTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
            }

            guard !composition.tracks(withMediaType: .video).isEmpty else {
                throw LiveError.noVideoTrack
            }
            exportAsset = composition
        }

        guard let session = AVAssetExportSession(
            asset: exportAsset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw LiveError.exportSession
        }

        let idItem = AVMutableMetadataItem()
        idItem.keySpace = .quickTimeMetadata
        idItem.key = "com.apple.quicktime.content.identifier" as NSString
        idItem.value = uuid as NSString
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"

        let timeItem = AVMutableMetadataItem()
        timeItem.keySpace = .quickTimeMetadata
        timeItem.key = "com.apple.quicktime.still-image-time" as NSString
        timeItem.value = NSNumber(value: Float(max(0, coverOffset)))
        timeItem.dataType = "com.apple.metadata.datatype.float32"

        session.metadata = [idItem, timeItem]
        session.outputURL = url
        session.outputFileType = .mov
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: clipStart, preferredTimescale: 600),
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )
        await session.export()

        if let e = session.error { throw LiveError.exportFailed(e.localizedDescription) }
        guard session.status == .completed else {
            throw LiveError.exportFailed("status=\(session.status.rawValue)")
        }
    }
}

func supportedVideo(_ url: URL) -> Bool {
    ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
}

func processOne(
    _ input: URL,
    output: URL,
    coverSeconds: Double? = nil,
    clipStart: Double? = nil,
    clipDuration: Double? = nil,
    includeAudio: Bool = true,
    preferredStem: String? = nil
) async -> Bool {
    do {
        let result = try await LivePhotoExporter().export(
            input: input,
            outputDirectory: output,
            requestedCoverSeconds: coverSeconds,
            requestedStartSeconds: clipStart,
            requestedDuration: clipDuration,
            includeAudio: includeAudio,
            preferredStem: preferredStem
        )
        print([
            "OK",
            input.lastPathComponent,
            result.imageURL.lastPathComponent,
            result.videoURL.lastPathComponent,
            String(format: "%.6f", result.coverSeconds),
            String(format: "%.6f", result.clipStart),
            String(format: "%.6f", result.clipDuration)
        ].joined(separator: "\t"))
        return true
    } catch {
        fputs("ERROR\t\(input.path)\t\(error)\n", stderr)
        return false
    }
}

@main
struct Main {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            print("Usage:")
            print("  spp-live-export [--cover seconds] [--start seconds] [--duration seconds] [--mute] [--stem name] <video> [output_dir]")
            print("  spp-live-export --batch <input_dir> <output_dir>")
            exit(2)
        }

        if args[0] == "--batch" {
            guard args.count >= 3 else { exit(2) }
            let inputDir = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
            let outputDir = URL(fileURLWithPath: NSString(string: args[2]).expandingTildeInPath)
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil)) ?? []
            let videos = files.filter(supportedVideo).sorted { $0.lastPathComponent < $1.lastPathComponent }
            print("Found \(videos.count) video(s)")
            var ok = 0
            for video in videos {
                if await processOne(video, output: outputDir) { ok += 1 }
            }
            print("DONE\t\(ok)/\(videos.count)")
            exit(ok == videos.count ? 0 : 1)
        }

        var coverSeconds: Double?
        var clipStart: Double?
        var clipDuration: Double?
        var includeAudio = true
        var preferredStem: String?
        var index = 0
        while index < args.count, args[index].hasPrefix("--") {
            switch args[index] {
            case "--cover":
                guard index + 1 < args.count, let value = Double(args[index + 1]) else { exit(2) }
                coverSeconds = value
                index += 2
            case "--start":
                guard index + 1 < args.count, let value = Double(args[index + 1]), value >= 0 else { exit(2) }
                clipStart = value
                index += 2
            case "--duration":
                guard index + 1 < args.count, let value = Double(args[index + 1]), value > 0 else { exit(2) }
                clipDuration = value
                index += 2
            case "--mute":
                includeAudio = false
                index += 1
            case "--stem":
                guard index + 1 < args.count else { exit(2) }
                preferredStem = args[index + 1]
                index += 2
            default:
                fputs("Unknown option: \(args[index])\n", stderr)
                exit(2)
            }
        }

        guard index < args.count else { exit(2) }
        let input = URL(fileURLWithPath: NSString(string: args[index]).expandingTildeInPath)
        let output = index + 1 < args.count
            ? URL(fileURLWithPath: NSString(string: args[index + 1]).expandingTildeInPath)
            : input.deletingLastPathComponent()
        let ok = await processOne(
            input,
            output: output,
            coverSeconds: coverSeconds,
            clipStart: clipStart,
            clipDuration: clipDuration,
            includeAudio: includeAudio,
            preferredStem: preferredStem
        )
        exit(ok ? 0 : 1)
    }
}
