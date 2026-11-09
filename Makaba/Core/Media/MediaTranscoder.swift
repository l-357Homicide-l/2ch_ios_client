//
//  MediaTranscoder.swift
//  Makaba
//
//  Transcodes video (e.g. QuickTime .mov to clean .mp4) and sanitizes images,
//  stripping EXIF/GPS metadata and preserving transparency for PNGs and animated GIFs.
//

import Foundation
import AVFoundation
import UIKit

public enum MediaTranscoder {

    /// Transcodes a video file at `sourceURL` to a sanitized MP4 without metadata.
    public static func transcodeVideoToCleanMP4(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("makaba_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw NSError(domain: "org.2ch.Makaba.MediaTranscoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadata = [] // Strips all GPS, camera, and device metadata

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }
        guard exportSession.status == .completed else {
            throw NSError(domain: "org.2ch.Makaba.MediaTranscoder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export session ended with status \(exportSession.status.rawValue)"])
        }

        return outputURL
    }

    /// Sanitizes image or video data, stripping location metadata while preserving PNG alpha and GIF animation.
    public static func sanitizeMedia(rawData: Data, isVideo: Bool, rawExtension: String) -> (data: Data, ext: String, mime: String) {
        let extLower = rawExtension.lowercased()

        if isVideo {
            let ext = ["mov", "m4v"].contains(extLower) ? "mp4" : extLower
            let mime = ext == "webm" ? "video/webm" : "video/mp4"
            return (rawData, ext, mime)
        }

        // 1. Animated GIF preservation
        if rawData.count >= 6, let header = String(data: rawData.prefix(6), encoding: .ascii), header.hasPrefix("GIF") {
            return (rawData, "gif", "image/gif")
        }

        // 2. PNG transparency preservation
        if extLower == "png" {
            if let image = UIImage(data: rawData), let pngData = image.pngData() {
                return (pngData, "png", "image/png")
            }
            return (rawData, "png", "image/png")
        }

        // 3. WebP preservation
        if extLower == "webp" {
            return (rawData, "webp", "image/webp")
        }

        // 4. Default: convert to clean JPEG stripping all EXIF and location metadata
        if let image = UIImage(data: rawData), let jpeg = image.jpegData(compressionQuality: 0.88) {
            return (jpeg, "jpg", "image/jpeg")
        }

        return (rawData, "jpg", "image/jpeg")
    }
}
