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

struct LivePhotoExporter {
    func export(input: URL, outputDirectory: URL) async throws -> (URL, URL) {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { throw LiveError.invalidDuration }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw LiveError.noVideoTrack }

        let coverSeconds = seconds / 2.0
        let coverTime = CMTime(seconds: coverSeconds, preferredTimescale: 600)
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
        var stem = "\(safeBase)_LIVE"
        var index = 2
        while fm.fileExists(atPath: outputDirectory.appendingPathComponent(stem + ".heic").path)
           || fm.fileExists(atPath: outputDirectory.appendingPathComponent(stem + ".mov").path) {
            stem = "\(safeBase)_LIVE_\(index)"
            index += 1
        }
        let imageURL = outputDirectory.appendingPathComponent(stem + ".heic")
        let videoURL = outputDirectory.appendingPathComponent(stem + ".mov")

        do {
            try writeHEIC(image: coverImage, uuid: uuid, to: imageURL)
            try await writeMOV(asset: asset, uuid: uuid, coverOffset: coverSeconds, to: videoURL)
            return (imageURL, videoURL)
        } catch {
            // Only clean files created by this failed export. Source media is never touched.
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

    private func writeMOV(asset: AVAsset, uuid: String, coverOffset: Double, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
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

func processOne(_ input: URL, output: URL) async -> Bool {
    do {
        let result = try await LivePhotoExporter().export(input: input, outputDirectory: output)
        print("OK\t\(input.lastPathComponent)\t\(result.0.lastPathComponent)\t\(result.1.lastPathComponent)")
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
            print("  spp-live-export <video> [output_dir]")
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
        } else {
            let input = URL(fileURLWithPath: NSString(string: args[0]).expandingTildeInPath)
            let output = args.count >= 2
                ? URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
                : input.deletingLastPathComponent()
            let ok = await processOne(input, output: output)
            exit(ok ? 0 : 1)
        }
    }
}
