//
//  Board.swift
//  Makaba
//
//  Authoritative board models for the 2ch.org (Makaba engine) API.
//

import Foundation

/// Represents an individual board icon definition (e.g., faction or custom badges on /po/, /vg/).
public struct BoardIcon: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let url: String

    public init(id: Int, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }

    /// Full URL for the icon asset.
    public var iconURL: URL? {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        let cleanPath = url.hasPrefix("/") ? url : "/\(url)"
        return DomainConfigurationService.shared.buildURL(path: cleanPath)
    }
}

/// Represents a 2ch.org board and its complete metadata configuration.
public struct Board: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let bumpLimit: Int
    public let defaultName: String
    public let enableDices: Bool
    public let enableFlags: Bool
    public let enableIcons: Bool
    public let enableLikes: Bool
    public let enableNames: Bool
    public let enableOekaki: Bool
    public let enablePosting: Bool
    public let enableSage: Bool
    public let enableShield: Bool
    public let enableSubject: Bool
    public let enableThreadTags: Bool
    public let enableTrips: Bool
    public let fileTypes: [String]
    public let info: String
    public let infoOuter: String
    public let maxComment: Int
    public let maxFilesSize: Int
    public let maxPages: Int
    public let threadsPerPage: Int
    public let tags: [String]?
    public let icons: [BoardIcon]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case bumpLimit = "bump_limit"
        case defaultName = "default_name"
        case enableDices = "enable_dices"
        case enableFlags = "enable_flags"
        case enableIcons = "enable_icons"
        case enableLikes = "enable_likes"
        case enableNames = "enable_names"
        case enableOekaki = "enable_oekaki"
        case enablePosting = "enable_posting"
        case enableSage = "enable_sage"
        case enableShield = "enable_shield"
        case enableSubject = "enable_subject"
        case enableThreadTags = "enable_thread_tags"
        case enableTrips = "enable_trips"
        case fileTypes = "file_types"
        case info
        case infoOuter = "info_outer"
        case maxComment = "max_comment"
        case maxFilesSize = "max_files_size"
        case maxPages = "max_pages"
        case threadsPerPage = "threads_per_page"
        case tags
        case icons
    }

    public init(
        id: String,
        name: String,
        category: String,
        bumpLimit: Int,
        defaultName: String = "Аноним",
        enableDices: Bool = false,
        enableFlags: Bool = false,
        enableIcons: Bool = false,
        enableLikes: Bool = false,
        enableNames: Bool = false,
        enableOekaki: Bool = false,
        enablePosting: Bool = true,
        enableSage: Bool = true,
        enableShield: Bool = false,
        enableSubject: Bool = true,
        enableThreadTags: Bool = false,
        enableTrips: Bool = false,
        fileTypes: [String] = ["jpg", "png", "gif", "webm", "mp4"],
        info: String = "",
        infoOuter: String = "",
        maxComment: Int = 15000,
        maxFilesSize: Int = 20480,
        maxPages: Int = 10,
        threadsPerPage: Int = 20,
        tags: [String]? = nil,
        icons: [BoardIcon]? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.bumpLimit = bumpLimit
        self.defaultName = defaultName
        self.enableDices = enableDices
        self.enableFlags = enableFlags
        self.enableIcons = enableIcons
        self.enableLikes = enableLikes
        self.enableNames = enableNames
        self.enableOekaki = enableOekaki
        self.enablePosting = enablePosting
        self.enableSage = enableSage
        self.enableShield = enableShield
        self.enableSubject = enableSubject
        self.enableThreadTags = enableThreadTags
        self.enableTrips = enableTrips
        self.fileTypes = fileTypes
        self.info = info
        self.infoOuter = infoOuter
        self.maxComment = maxComment
        self.maxFilesSize = maxFilesSize
        self.maxPages = maxPages
        self.threadsPerPage = threadsPerPage
        self.tags = tags
        self.icons = icons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.category = (try? container.decode(String.self, forKey: .category)) ?? "Общее"
        self.bumpLimit = (try? container.decode(Int.self, forKey: .bumpLimit)) ?? 500
        self.defaultName = (try? container.decode(String.self, forKey: .defaultName)) ?? "Аноним"

        // Handle boolean fields which Makaba returns as either Bool or Int (0/1)
        self.enableDices = Self.decodeFlexibleBool(container: container, key: .enableDices)
        self.enableFlags = Self.decodeFlexibleBool(container: container, key: .enableFlags)
        self.enableIcons = Self.decodeFlexibleBool(container: container, key: .enableIcons)
        self.enableLikes = Self.decodeFlexibleBool(container: container, key: .enableLikes)
        self.enableNames = Self.decodeFlexibleBool(container: container, key: .enableNames)
        self.enableOekaki = Self.decodeFlexibleBool(container: container, key: .enableOekaki)
        self.enablePosting = Self.decodeFlexibleBool(container: container, key: .enablePosting, defaultValue: true)
        self.enableSage = Self.decodeFlexibleBool(container: container, key: .enableSage, defaultValue: true)
        self.enableShield = Self.decodeFlexibleBool(container: container, key: .enableShield)
        self.enableSubject = Self.decodeFlexibleBool(container: container, key: .enableSubject, defaultValue: true)
        self.enableThreadTags = Self.decodeFlexibleBool(container: container, key: .enableThreadTags)
        self.enableTrips = Self.decodeFlexibleBool(container: container, key: .enableTrips)

        self.fileTypes = (try? container.decode([String].self, forKey: .fileTypes)) ?? ["jpg", "png", "gif", "webm", "mp4"]
        self.info = (try? container.decode(String.self, forKey: .info)) ?? ""
        self.infoOuter = (try? container.decode(String.self, forKey: .infoOuter)) ?? ""
        self.maxComment = (try? container.decode(Int.self, forKey: .maxComment)) ?? 15000
        self.maxFilesSize = (try? container.decode(Int.self, forKey: .maxFilesSize)) ?? 20480
        self.maxPages = (try? container.decode(Int.self, forKey: .maxPages)) ?? 10
        self.threadsPerPage = (try? container.decode(Int.self, forKey: .threadsPerPage)) ?? 20
        self.tags = try? container.decode([String].self, forKey: .tags)
        self.icons = try? container.decode([BoardIcon].self, forKey: .icons)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(bumpLimit, forKey: .bumpLimit)
        try container.encode(defaultName, forKey: .defaultName)
        try container.encode(enableDices, forKey: .enableDices)
        try container.encode(enableFlags, forKey: .enableFlags)
        try container.encode(enableIcons, forKey: .enableIcons)
        try container.encode(enableLikes, forKey: .enableLikes)
        try container.encode(enableNames, forKey: .enableNames)
        try container.encode(enableOekaki, forKey: .enableOekaki)
        try container.encode(enablePosting, forKey: .enablePosting)
        try container.encode(enableSage, forKey: .enableSage)
        try container.encode(enableShield, forKey: .enableShield)
        try container.encode(enableSubject, forKey: .enableSubject)
        try container.encode(enableThreadTags, forKey: .enableThreadTags)
        try container.encode(enableTrips, forKey: .enableTrips)
        try container.encode(fileTypes, forKey: .fileTypes)
        try container.encode(info, forKey: .info)
        try container.encode(infoOuter, forKey: .infoOuter)
        try container.encode(maxComment, forKey: .maxComment)
        try container.encode(maxFilesSize, forKey: .maxFilesSize)
        try container.encode(maxPages, forKey: .maxPages)
        try container.encode(threadsPerPage, forKey: .threadsPerPage)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(icons, forKey: .icons)
    }

    private static func decodeFlexibleBool(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        defaultValue: Bool = false
    ) -> Bool {
        if let boolVal = try? container.decode(Bool.self, forKey: key) {
            return boolVal
        }
        if let intVal = try? container.decode(Int.self, forKey: key) {
            return intVal != 0
        }
        if let strVal = try? container.decode(String.self, forKey: key) {
            return strVal == "1" || strVal.lowercased() == "true"
        }
        return defaultValue
    }
    // MARK: - Dynamic Defunct Board Registry

    /// Known boards permanently removed or returning HTTP 500 on 2ch.
    public static let knownDefunctBoardIDs: Set<String> = [
        "fur", "vn", "ho", "h", "r34", "hg", "e", "ruvn", "fet", "nf"
    ]

    private static let defunctLock = NSLock()
    private static var dynamicDefunctBoardIDs: Set<String> = knownDefunctBoardIDs

    /// Dynamically flags a board as defunct when receiving HTTP 404/410 or permanent deprecation redirects.
    public static func markDefunct(boardId: String) {
        defunctLock.lock()
        dynamicDefunctBoardIDs.insert(boardId.lowercased())
        defunctLock.unlock()
    }

    /// Clears defunct flag when a board responds with active threads.
    public static func markActive(boardId: String) {
        defunctLock.lock()
        dynamicDefunctBoardIDs.remove(boardId.lowercased())
        defunctLock.unlock()
    }

    /// Dynamically discovered and known defunct boards based on runtime HTTP status.
    public static var defunctBoardIDs: Set<String> {
        defunctLock.lock()
        defer { defunctLock.unlock() }
        return dynamicDefunctBoardIDs.union(knownDefunctBoardIDs)
    }

    /// Whether this board has been determined defunct by network status or known archive list.
    public var isDefunct: Bool {
        Self.defunctLock.lock()
        defer { Self.defunctLock.unlock() }
        let lower = id.lowercased()
        return Self.knownDefunctBoardIDs.contains(lower) || Self.dynamicDefunctBoardIDs.contains(lower)
    }

    // MARK: - Equatable & Hashable Identity

    public static func == (lhs: Board, rhs: Board) -> Bool {
        lhs.id.caseInsensitiveCompare(rhs.id) == .orderedSame
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id.lowercased())
    }
}

/// Represents a taxonomic grouping of boards by category name.
public struct BoardCategory: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let boards: [Board]

    public init(name: String, boards: [Board]) {
        self.name = name
        self.boards = boards
    }

    /// Organizes a flat list of boards into sorted categorical groups, isolating defunct boards.
    public static func groupByCategory(_ boards: [Board]) -> [BoardCategory] {
        let activeBoards = boards.filter { !$0.isDefunct }
        let grouped = Dictionary(grouping: activeBoards, by: { $0.category })
        // Maintain consistent category ordering
        let standardOrder = [
            "Разное",
            "Тематика",
            "Творчество",
            "Политика",
            "Техника и софт",
            "Игры",
            "Японская культура",
            "Взрослым",
            "Пользовательские"
        ]

        var categories: [BoardCategory] = []
        var processed = Set<String>()

        for name in standardOrder {
            if let list = grouped[name], !list.isEmpty {
                let sortedList = list.sorted { $0.id < $1.id }
                categories.append(BoardCategory(name: name, boards: sortedList))
                processed.insert(name)
            }
        }

        let remainingNames = grouped.keys.filter { !processed.contains($0) }.sorted()
        for name in remainingNames {
            if let list = grouped[name], !list.isEmpty {
                let sortedList = list.sorted { $0.id < $1.id }
                categories.append(BoardCategory(name: name, boards: sortedList))
            }
        }

        // Add defunct / archived boards under a dedicated section at the bottom
        let defunctBoards = boards.filter { $0.isDefunct }.sorted { $0.id < $1.id }
        if !defunctBoards.isEmpty {
            categories.append(BoardCategory(name: "Архивные / закрытые на 2ch", boards: defunctBoards))
        }

        return categories
    }
}
