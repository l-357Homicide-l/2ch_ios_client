//
//  Post.swift
//  Makaba
//
//  Authoritative post model matching the 2ch.org (Makaba engine) post schema.
//

import Foundation

/// Represents a single post within a 2ch.org thread.
public struct Post: Codable, Identifiable, Hashable, Sendable {
    public var id: Int { num }

    public let num: Int
    public let number: Int?
    public let parent: Int?
    public let banned: Int?
    public let closed: Int?
    public let date: String
    public let timestamp: Int
    public let name: String
    public let trip: String?
    public let email: String?
    public let subject: String?
    public let comment: String
    public let op: Int?
    public let sticky: Int?
    public let endless: Int?
    public let tags: String?
    public let views: Int?
    public let lasthit: Int?
    public let likes: Int?
    public let dislikes: Int?
    public let files: [MediaFile]
    public let icon: String?

    enum CodingKeys: String, CodingKey {
        case num
        case number
        case parent
        case banned
        case closed
        case date
        case timestamp
        case name
        case trip
        case email
        case subject
        case comment
        case op
        case sticky
        case endless
        case tags
        case views
        case lasthit
        case likes
        case dislikes
        case files
        case icon
    }

    public init(
        num: Int,
        number: Int? = nil,
        parent: Int? = 0,
        banned: Int? = 0,
        closed: Int? = 0,
        date: String = "",
        timestamp: Int = 0,
        name: String = "Аноним",
        trip: String? = nil,
        email: String? = nil,
        subject: String? = nil,
        comment: String = "",
        op: Int? = 0,
        sticky: Int? = 0,
        endless: Int? = 0,
        tags: String? = nil,
        views: Int? = nil,
        lasthit: Int? = nil,
        likes: Int? = 0,
        dislikes: Int? = 0,
        files: [MediaFile] = [],
        icon: String? = nil
    ) {
        self.num = num
        self.number = number
        self.parent = parent
        self.banned = banned
        self.closed = closed
        self.date = date
        self.timestamp = timestamp
        self.name = name
        self.trip = trip
        self.email = email
        self.subject = subject
        self.comment = comment
        self.op = op
        self.sticky = sticky
        self.endless = endless
        self.tags = tags
        self.views = views
        self.lasthit = lasthit
        self.likes = likes
        self.dislikes = dislikes
        self.files = files
        self.icon = icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.num = try container.decode(Int.self, forKey: .num)
        self.number = try? container.decode(Int.self, forKey: .number)
        self.parent = try? container.decode(Int.self, forKey: .parent)
        self.banned = try? container.decode(Int.self, forKey: .banned)
        self.closed = try? container.decode(Int.self, forKey: .closed)
        self.date = (try? container.decode(String.self, forKey: .date)) ?? ""
        self.timestamp = (try? container.decode(Int.self, forKey: .timestamp)) ?? 0
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Аноним"
        self.trip = try? container.decode(String.self, forKey: .trip)
        self.email = try? container.decode(String.self, forKey: .email)
        self.subject = try? container.decode(String.self, forKey: .subject)
        self.comment = (try? container.decode(String.self, forKey: .comment)) ?? ""
        self.op = try? container.decode(Int.self, forKey: .op)
        self.sticky = try? container.decode(Int.self, forKey: .sticky)
        self.endless = try? container.decode(Int.self, forKey: .endless)
        self.tags = try? container.decode(String.self, forKey: .tags)
        self.views = try? container.decode(Int.self, forKey: .views)
        self.lasthit = try? container.decode(Int.self, forKey: .lasthit)
        self.likes = try? container.decode(Int.self, forKey: .likes)
        self.dislikes = try? container.decode(Int.self, forKey: .dislikes)
        
        // Lossy decoding: resilient element-by-element parsing prevents a single malformed file from discarding all attachments
        if let lossyFiles = try? container.decode([LossyMediaFile].self, forKey: .files) {
            self.files = lossyFiles.compactMap(\.value)
        } else {
            self.files = (try? container.decode([MediaFile].self, forKey: .files)) ?? []
        }

        // Flexible decoding for `icon` which may be an Int or String or missing
        if let iconInt = try? container.decode(Int.self, forKey: .icon) {
            self.icon = String(iconInt)
        } else {
            self.icon = try? container.decode(String.self, forKey: .icon)
        }
    }

    // MARK: - Computed Properties

    /// Whether this post is the thread's original post (OP).
    public var isOP: Bool {
        return (op ?? 0) == 1 || parent == 0 || (number ?? 0) == 1
    }

    /// Whether the poster submitted with sage (no bump).
    public var isSage: Bool {
        guard let email = email else { return false }
        return email.lowercased().contains("sage")
    }

    /// Whether this post or author was marked banned by moderators.
    public var isBanned: Bool {
        return (banned ?? 0) != 0
    }

    /// Net vote score (likes - dislikes).
    public var score: Int {
        return (likes ?? 0) - (dislikes ?? 0)
    }

    /// Whether this post has any media file attachments.
    public var hasFiles: Bool {
        return !files.isEmpty
    }

    /// Sanitized display subject (fallback to first line of comment or empty).
    public var displaySubject: String {
        if let subj = subject, !subj.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subj
        }
        return ""
    }

    /// Extract target post IDs referenced by this post's HTML comment (e.g., `>>338026307`).
    public var referencedPostNumbers: [Int] {
        return MakabaHTMLParser.extractQuoteNumbers(html: comment)
    }
}

/// Resilient decoder wrapper that tolerates single malformed attachment payloads.
public struct LossyMediaFile: Decodable, Sendable {
    public let value: MediaFile?

    public init(from decoder: Decoder) throws {
        let container = try? decoder.singleValueContainer()
        self.value = try? container?.decode(MediaFile.self)
    }
}
