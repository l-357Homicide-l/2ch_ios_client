//
//  Catalog.swift
//  Makaba
//
//  Board catalog response and thread preview item models for 2ch.org.
//

import Foundation

/// A thread preview item in the board catalog (`/{board}/catalog.json`).
public struct CatalogThreadItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Int { num }

    public let num: Int
    public let parent: Int?
    public let board: String?
    public let subject: String
    public let comment: String
    public let date: String
    public let timestamp: Int
    public let lasthit: Int
    public let views: Int
    public let postsCount: Int
    public let filesCount: Int
    public let banned: Int?
    public let closed: Int?
    public let endless: Int?
    public let sticky: Int?
    public let op: Int?
    public let name: String?
    public let trip: String?
    public let email: String?
    public let tags: String?
    public let files: [MediaFile]
    public let score: Double?

    enum CodingKeys: String, CodingKey {
        case num
        case parent
        case board
        case subject
        case comment
        case date
        case timestamp
        case lasthit
        case views
        case postsCount = "posts_count"
        case filesCount = "files_count"
        case banned
        case closed
        case endless
        case sticky
        case op
        case name
        case trip
        case email
        case tags
        case files
        case score
    }

    public init(
        num: Int,
        parent: Int? = 0,
        board: String? = nil,
        subject: String = "",
        comment: String = "",
        date: String = "",
        timestamp: Int = 0,
        lasthit: Int = 0,
        views: Int = 0,
        postsCount: Int = 0,
        filesCount: Int = 0,
        banned: Int? = 0,
        closed: Int? = 0,
        endless: Int? = 0,
        sticky: Int? = 0,
        op: Int? = 1,
        name: String? = nil,
        trip: String? = nil,
        email: String? = nil,
        tags: String? = nil,
        files: [MediaFile] = [],
        score: Int? = 0
    ) {
        self.num = num
        self.parent = parent
        self.board = board
        self.subject = subject
        self.comment = comment
        self.date = date
        self.timestamp = timestamp
        self.lasthit = lasthit
        self.views = views
        self.postsCount = postsCount
        self.filesCount = filesCount
        self.banned = banned
        self.closed = closed
        self.endless = endless
        self.sticky = sticky
        self.op = op
        self.name = name
        self.trip = trip
        self.email = email
        self.tags = tags
        self.files = files
        self.score = score
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.num = try container.decode(Int.self, forKey: .num)
        self.parent = try? container.decode(Int.self, forKey: .parent)
        self.board = try? container.decode(String.self, forKey: .board)
        self.subject = (try? container.decode(String.self, forKey: .subject)) ?? ""
        self.comment = (try? container.decode(String.self, forKey: .comment)) ?? ""
        self.date = (try? container.decode(String.self, forKey: .date)) ?? ""
        self.timestamp = (try? container.decode(Int.self, forKey: .timestamp)) ?? 0
        self.lasthit = (try? container.decode(Int.self, forKey: .lasthit)) ?? 0
        self.views = (try? container.decode(Int.self, forKey: .views)) ?? 0
        self.postsCount = (try? container.decode(Int.self, forKey: .postsCount)) ?? 0
        self.filesCount = (try? container.decode(Int.self, forKey: .filesCount)) ?? 0
        self.banned = try? container.decode(Int.self, forKey: .banned)
        self.closed = try? container.decode(Int.self, forKey: .closed)
        self.endless = try? container.decode(Int.self, forKey: .endless)
        self.sticky = try? container.decode(Int.self, forKey: .sticky)
        self.op = try? container.decode(Int.self, forKey: .op)
        self.name = try? container.decode(String.self, forKey: .name)
        self.trip = try? container.decode(String.self, forKey: .trip)
        self.email = try? container.decode(String.self, forKey: .email)
        self.tags = try? container.decode(String.self, forKey: .tags)
        if let lossyFiles = try? container.decode([LossyMediaFile].self, forKey: .files) {
            self.files = lossyFiles.compactMap(\.value)
        } else {
            self.files = (try? container.decode([MediaFile].self, forKey: .files)) ?? []
        }
        if let doubleScore = try? container.decode(Double.self, forKey: .score) {
            self.score = doubleScore
        } else if let intScore = try? container.decode(Int.self, forKey: .score) {
            self.score = Double(intScore)
        } else {
            self.score = nil
        }
    }

    // MARK: - Computed Properties

    /// Whether this thread is pinned/stickied.
    public var isPinned: Bool {
        return (sticky ?? 0) > 0
    }

    /// Whether this thread is closed to new replies.
    public var isLocked: Bool {
        return (closed ?? 0) != 0
    }

    /// Whether this is an endless bump thread.
    public var isEndless: Bool {
        return (endless ?? 0) != 0
    }

    /// Primary thumbnail / media attachment.
    public var primaryFile: MediaFile? {
        return files.first
    }

    /// Stripped plain-text comment representation for reliable search indexing.
    public var plainTextComment: String {
        return MakabaHTMLParser.toPlainText(html: comment)
    }

    /// Subject line or clean excerpt from comment.
    public var displayTitle: String {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSubject.isEmpty {
            return cleanSubject
        }
        return "Тред #\(num)"
    }
}

/// Catalog response wrapping threads and board metadata (`/{board}/catalog.json`).
public struct CatalogResponse: Codable, Hashable, Sendable {
    public let filter: String?
    public let advertTopImage: String?
    public let advertTopLink: String?
    public let advertBottomImage: String?
    public let advertBottomLink: String?
    public let boardBannerImage: String?
    public let boardBannerLink: String?
    public let threads: [CatalogThreadItem]

    enum CodingKeys: String, CodingKey {
        case filter
        case advertTopImage = "advert_top_image"
        case advertTopLink = "advert_top_link"
        case advertBottomImage = "advert_bottom_image"
        case advertBottomLink = "advert_bottom_link"
        case boardBannerImage = "board_banner_image"
        case boardBannerLink = "board_banner_link"
        case threads
    }

    public init(
        filter: String? = "standart",
        advertTopImage: String? = nil,
        advertTopLink: String? = nil,
        advertBottomImage: String? = nil,
        advertBottomLink: String? = nil,
        boardBannerImage: String? = nil,
        boardBannerLink: String? = nil,
        threads: [CatalogThreadItem] = []
    ) {
        self.filter = filter
        self.advertTopImage = advertTopImage
        self.advertTopLink = advertTopLink
        self.advertBottomImage = advertBottomImage
        self.advertBottomLink = advertBottomLink
        self.boardBannerImage = boardBannerImage
        self.boardBannerLink = boardBannerLink
        self.threads = threads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.filter = try? container.decode(String.self, forKey: .filter)
        self.advertTopImage = try? container.decode(String.self, forKey: .advertTopImage)
        self.advertTopLink = try? container.decode(String.self, forKey: .advertTopLink)
        self.advertBottomImage = try? container.decode(String.self, forKey: .advertBottomImage)
        self.advertBottomLink = try? container.decode(String.self, forKey: .advertBottomLink)
        self.boardBannerImage = try? container.decode(String.self, forKey: .boardBannerImage)
        self.boardBannerLink = try? container.decode(String.self, forKey: .boardBannerLink)
        self.threads = (try? container.decode([CatalogThreadItem].self, forKey: .threads)) ?? []
    }
}
