//
//  Thread.swift
//  Makaba
//
//  Thread response models and thread list representations for 2ch.org.
//

import Foundation

/// Container wrapping posts in a thread response.
public struct ThreadPostsContainer: Codable, Hashable, Sendable {
    public let posts: [Post]

    public init(posts: [Post]) {
        self.posts = posts
    }
}

/// Full thread response matching `/{board}/res/{thread_num}.json`.
public struct ThreadResponse: Codable, Hashable, Sendable {
    public let currentThread: String?
    public let filesCount: Int
    public let postsCount: Int
    public let maxNum: Int?
    public let title: String?
    public let uniquePosters: String?
    public let isBoard: Int?
    public let isClosed: Int?
    public let isIndex: Int?
    public let threads: [ThreadPostsContainer]

    enum CodingKeys: String, CodingKey {
        case currentThread = "current_thread"
        case filesCount = "files_count"
        case postsCount = "posts_count"
        case maxNum = "max_num"
        case title
        case uniquePosters = "unique_posters"
        case isBoard = "is_board"
        case isClosed = "is_closed"
        case isIndex = "is_index"
        case threads
    }

    public init(
        currentThread: String? = nil,
        filesCount: Int = 0,
        postsCount: Int = 0,
        maxNum: Int? = nil,
        title: String? = nil,
        uniquePosters: String? = nil,
        isBoard: Int? = 0,
        isClosed: Int? = 0,
        isIndex: Int? = 0,
        threads: [ThreadPostsContainer] = []
    ) {
        self.currentThread = currentThread
        self.filesCount = filesCount
        self.postsCount = postsCount
        self.maxNum = maxNum
        self.title = title
        self.uniquePosters = uniquePosters
        self.isBoard = isBoard
        self.isClosed = isClosed
        self.isIndex = isIndex
        self.threads = threads
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let str = try? container.decode(String.self, forKey: .currentThread) {
            self.currentThread = str
        } else if let intVal = try? container.decode(Int.self, forKey: .currentThread) {
            self.currentThread = String(intVal)
        } else {
            self.currentThread = nil
        }

        self.filesCount = (try? container.decode(Int.self, forKey: .filesCount)) ?? 0
        self.postsCount = (try? container.decode(Int.self, forKey: .postsCount)) ?? 0
        self.maxNum = try? container.decode(Int.self, forKey: .maxNum)
        self.title = try? container.decode(String.self, forKey: .title)

        if let postersStr = try? container.decode(String.self, forKey: .uniquePosters) {
            self.uniquePosters = postersStr
        } else if let postersInt = try? container.decode(Int.self, forKey: .uniquePosters) {
            self.uniquePosters = String(postersInt)
        } else {
            self.uniquePosters = nil
        }

        self.isBoard = try? container.decode(Int.self, forKey: .isBoard)
        self.isClosed = try? container.decode(Int.self, forKey: .isClosed)
        self.isIndex = try? container.decode(Int.self, forKey: .isIndex)
        self.threads = (try? container.decode([ThreadPostsContainer].self, forKey: .threads)) ?? []
    }

    // MARK: - Computed Properties

    /// All posts contained in the thread.
    public var posts: [Post] {
        return threads.first?.posts ?? []
    }

    /// The Original Post (OP) of this thread.
    public var opPost: Post? {
        return posts.first
    }

    /// Numerical ID of the thread.
    public var threadNum: Int {
        if let op = opPost {
            return op.num
        }
        if let current = currentThread, let num = Int(current) {
            return num
        }
        return 0
    }

    /// Whether the thread is locked against new replies.
    public var isLocked: Bool {
        return (isClosed ?? 0) != 0 || (opPost?.closed ?? 0) != 0
    }
}

/// Item in the lightweight flat thread list response (`/{board}/threads.json`).
public struct ThreadListItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Int { num }

    public let num: Int
    public let subject: String
    public let comment: String
    public let timestamp: Int
    public let lasthit: Int
    public let postsCount: Int
    public let filesCount: Int?
    public let views: Int?
    public let score: Double?

    enum CodingKeys: String, CodingKey {
        case num
        case subject
        case comment
        case timestamp
        case lasthit
        case postsCount = "posts_count"
        case filesCount = "files_count"
        case views
        case score
    }

    public init(
        num: Int,
        subject: String = "",
        comment: String = "",
        timestamp: Int = 0,
        lasthit: Int = 0,
        postsCount: Int = 0,
        filesCount: Int? = 0,
        views: Int? = 0,
        score: Int? = 0
    ) {
        self.num = num
        self.subject = subject
        self.comment = comment
        self.timestamp = timestamp
        self.lasthit = lasthit
        self.postsCount = postsCount
        self.filesCount = filesCount
        self.views = views
        self.score = score
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.num = try container.decode(Int.self, forKey: .num)
        self.subject = (try? container.decode(String.self, forKey: .subject)) ?? ""
        self.comment = (try? container.decode(String.self, forKey: .comment)) ?? ""
        self.timestamp = (try? container.decode(Int.self, forKey: .timestamp)) ?? 0
        self.lasthit = (try? container.decode(Int.self, forKey: .lasthit)) ?? 0
        self.postsCount = (try? container.decode(Int.self, forKey: .postsCount)) ?? 0
        self.filesCount = try? container.decode(Int.self, forKey: .filesCount)
        self.views = try? container.decode(Int.self, forKey: .views)
        if let doubleScore = try? container.decode(Double.self, forKey: .score) {
            self.score = doubleScore
        } else if let intScore = try? container.decode(Int.self, forKey: .score) {
            self.score = Double(intScore)
        } else {
            self.score = nil
        }
    }
}

/// Response wrapper for `/{board}/threads.json`.
public struct ThreadListResponse: Codable, Hashable, Sendable {
    public let board: String
    public let threads: [ThreadListItem]

    public init(board: String, threads: [ThreadListItem]) {
        self.board = board
        self.threads = threads
    }
}
