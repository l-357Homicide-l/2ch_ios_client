//
//  MediaFile.swift
//  Makaba
//
//  Media file attachment model and type enumerations matching the 2ch.org schema.
//

import Foundation

/// Supported media attachment format categories.
public enum MediaType: Int, Codable, Hashable, Sendable {
    case jpeg = 1
    case png = 2
    case gif = 4
    case webm = 6
    case externalVideo = 7
    case webp = 9
    case mp4 = 10
    case sticker = 100
    case unknown = -1

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawVal = try container.decode(Int.self)
        self = MediaType(rawValue: rawVal) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Primary MIME content type string.
    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .gif: return "image/gif"
        case .webm: return "video/webm"
        case .externalVideo: return "text/html"
        case .webp: return "image/webp"
        case .mp4: return "video/mp4"
        case .sticker: return "image/png"
        case .unknown: return "application/octet-stream"
        }
    }
}

/// Represents an attached file (image, WebM, GIF, MP4, sticker) on a post.
public struct MediaFile: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }

    public let displayname: String?
    public let fullname: String?
    public let name: String
    public let path: String
    public let thumbnail: String?
    public let size: Int // Size in kilobytes
    public let width: Int
    public let height: Int
    public let tnWidth: Int
    public let tnHeight: Int
    public let type: MediaType
    public let duration: String?
    public let durationSecs: Int?
    public let md5: String?
    public let nsfw: Int?
    public let install: String?

    enum CodingKeys: String, CodingKey {
        case displayname
        case fullname
        case name
        case path
        case thumbnail
        case size
        case width
        case height
        case tnWidth = "tn_width"
        case tnHeight = "tn_height"
        case type
        case duration
        case durationSecs = "duration_secs"
        case md5
        case nsfw
        case install
    }

    public init(
        name: String,
        path: String,
        thumbnail: String? = nil,
        size: Int = 0,
        width: Int = 0,
        height: Int = 0,
        tnWidth: Int = 0,
        tnHeight: Int = 0,
        type: MediaType = .unknown,
        displayname: String? = nil,
        fullname: String? = nil,
        duration: String? = nil,
        durationSecs: Int? = nil,
        md5: String? = nil,
        nsfw: Int? = nil,
        install: String? = nil
    ) {
        self.name = name
        self.path = path
        self.thumbnail = thumbnail
        self.size = size
        self.width = width
        self.height = height
        self.tnWidth = tnWidth
        self.tnHeight = tnHeight
        self.type = type
        self.displayname = displayname
        self.fullname = fullname
        self.duration = duration
        self.durationSecs = durationSecs
        self.md5 = md5
        self.nsfw = nsfw
        self.install = install
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.thumbnail = try? container.decode(String.self, forKey: .thumbnail)
        self.size = (try? container.decode(Int.self, forKey: .size)) ?? 0
        self.width = (try? container.decode(Int.self, forKey: .width)) ?? 0
        self.height = (try? container.decode(Int.self, forKey: .height)) ?? 0
        self.tnWidth = (try? container.decode(Int.self, forKey: .tnWidth)) ?? 0
        self.tnHeight = (try? container.decode(Int.self, forKey: .tnHeight)) ?? 0

        self.type = (try? container.decode(MediaType.self, forKey: .type)) ?? .unknown
        self.displayname = try? container.decode(String.self, forKey: .displayname)
        self.fullname = try? container.decode(String.self, forKey: .fullname)
        self.duration = try? container.decode(String.self, forKey: .duration)
        self.durationSecs = try? container.decode(Int.self, forKey: .durationSecs)
        self.md5 = try? container.decode(String.self, forKey: .md5)
        self.nsfw = try? container.decode(Int.self, forKey: .nsfw)
        self.install = try? container.decode(String.self, forKey: .install)
    }

    // MARK: - Computed Properties

    /// Absolute URL pointing to the full-resolution asset with percent-encoding.
    public var fullURL: URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
            return URL(string: escaped)
        }
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        let escapedPath = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath
        return URL(string: "https://2ch.org\(escapedPath)")
    }

    /// Absolute URL pointing to the preview thumbnail (always JPEG) with percent-encoding.
    public var thumbnailURL: URL? {
        guard let thumb = thumbnail, !thumb.isEmpty else { return fullURL }
        if thumb.hasPrefix("http://") || thumb.hasPrefix("https://") {
            let escaped = thumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? thumb
            return URL(string: escaped)
        }
        let cleanPath = thumb.hasPrefix("/") ? thumb : "/\(thumb)"
        let escapedPath = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath
        return URL(string: "https://2ch.org\(escapedPath)")
    }

    /// Whether this file requires video playback engines.
    public var isVideo: Bool {
        return type == .webm || type == .mp4
    }

    /// Whether this file is a static or animated graphic.
    public var isImage: Bool {
        return type == .jpeg || type == .png || type == .gif || type == .webp || type == .sticker
    }

    /// Human-readable file size formatted as KB or MB.
    public var formattedSize: String {
        if size >= 1024 {
            let mb = Double(size) / 1024.0
            return String(format: "%.1f MB", mb)
        } else {
            return "\(size) KB"
        }
    }

    /// Video or image aspect ratio (width / height).
    public var aspectRatio: Double {
        guard height > 0 else { return 1.0 }
        return Double(width) / Double(height)
    }

    /// Thumbnail aspect ratio (tnWidth / tnHeight).
    public var thumbnailAspectRatio: Double {
        guard tnHeight > 0 else { return 1.0 }
        return Double(tnWidth) / Double(tnHeight)
    }
}
