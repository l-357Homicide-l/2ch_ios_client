//
//  DatabaseService.swift
//  Makaba
//
//  Production SQLite persistent storage engine for thread history, favorites, and post drafts.
//

import Foundation
import SQLite3

public struct HistoryEntry: Identifiable, Sendable {
    public var id: String { "\(board)_\(threadNum)" }
    public let board: String
    public let threadNum: Int
    public let title: String
    public let lastReadNum: Int
    public let updatedAt: Date
}

public struct FavoriteEntry: Identifiable, Sendable {
    public var id: String { "\(board)_\(threadNum)" }
    public let board: String
    public let threadNum: Int
    public let title: String
    public let addedAt: Date
}

public struct DraftEntry: Identifiable, Sendable {
    public var id: String { "\(board)_\(threadNum)" }
    public let board: String
    public let threadNum: Int
    public let comment: String
    public let name: String
    public let email: String
    public let updatedAt: Date
}

/// Actor-isolated thread-safe SQLite database service.
public actor DatabaseService {
    public static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let makabaDir = appSupport.appendingPathComponent("Makaba", isDirectory: true)

        if !fileManager.fileExists(atPath: makabaDir.path) {
            try? fileManager.createDirectory(at: makabaDir, withIntermediateDirectories: true)
        }

        let databaseURL = makabaDir.appendingPathComponent("makaba.sqlite")
        self.dbPath = databaseURL.path

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            createTables()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    nonisolated private func createTables() {
        let historySQL = """
        CREATE TABLE IF NOT EXISTS thread_history (
            board TEXT NOT NULL,
            thread_num INTEGER NOT NULL,
            title TEXT NOT NULL,
            last_read_num INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (board, thread_num)
        );
        """

        let favoritesSQL = """
        CREATE TABLE IF NOT EXISTS favorites (
            board TEXT NOT NULL,
            thread_num INTEGER NOT NULL,
            title TEXT NOT NULL,
            added_at REAL NOT NULL,
            PRIMARY KEY (board, thread_num)
        );
        """

        let draftsSQL = """
        CREATE TABLE IF NOT EXISTS drafts (
            board TEXT NOT NULL,
            thread_num INTEGER NOT NULL,
            comment TEXT NOT NULL,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (board, thread_num)
        );
        """

        executeSimple(historySQL)
        executeSimple(favoritesSQL)
        executeSimple(draftsSQL)
    }

    nonisolated private func executeSimple(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &errMsg)
        if let errMsg = errMsg {
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Thread History CRUD

    public func recordHistory(board: String, threadNum: Int, title: String, lastReadNum: Int) {
        let sql = """
        INSERT INTO thread_history (board, thread_num, title, last_read_num, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(board, thread_num) DO UPDATE SET
            title = excluded.title,
            last_read_num = excluded.last_read_num,
            updated_at = excluded.updated_at;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 4, Int64(lastReadNum))
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    public func getHistory(limit: Int = 100) -> [HistoryEntry] {
        let sql = "SELECT board, thread_num, title, last_read_num, updated_at FROM thread_history ORDER BY updated_at DESC LIMIT ?;"
        var results: [HistoryEntry] = []
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let boardPtr = sqlite3_column_text(statement, 0),
                      let titlePtr = sqlite3_column_text(statement, 2) else { continue }
                let board = String(cString: boardPtr)
                let threadNum = Int(sqlite3_column_int64(statement, 1))
                let title = String(cString: titlePtr)
                let lastRead = Int(sqlite3_column_int64(statement, 3))
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

                results.append(HistoryEntry(
                    board: board,
                    threadNum: threadNum,
                    title: title,
                    lastReadNum: lastRead,
                    updatedAt: date
                ))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    public func clearHistory() {
        executeSimple("DELETE FROM thread_history;")
    }

    // MARK: - Favorites CRUD

    public func toggleFavorite(board: String, threadNum: Int, title: String) -> Bool {
        if isFavorite(board: board, threadNum: threadNum) {
            removeFavorite(board: board, threadNum: threadNum)
            return false
        } else {
            addFavorite(board: board, threadNum: threadNum, title: title)
            return true
        }
    }

    public func isFavorite(board: String, threadNum: Int) -> Bool {
        let sql = "SELECT 1 FROM favorites WHERE board = ? AND thread_num = ? LIMIT 1;"
        var statement: OpaquePointer?
        var exists = false

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            if sqlite3_step(statement) == SQLITE_ROW {
                exists = true
            }
        }
        sqlite3_finalize(statement)
        return exists
    }

    public func addFavorite(board: String, threadNum: Int, title: String) {
        let sql = """
        INSERT OR REPLACE INTO favorites (board, thread_num, title, added_at)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    public func removeFavorite(board: String, threadNum: Int) {
        let sql = "DELETE FROM favorites WHERE board = ? AND thread_num = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    public func getFavorites() -> [FavoriteEntry] {
        let sql = "SELECT board, thread_num, title, added_at FROM favorites ORDER BY added_at DESC;"
        var results: [FavoriteEntry] = []
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let boardPtr = sqlite3_column_text(statement, 0),
                      let titlePtr = sqlite3_column_text(statement, 2) else { continue }
                let board = String(cString: boardPtr)
                let threadNum = Int(sqlite3_column_int64(statement, 1))
                let title = String(cString: titlePtr)
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))

                results.append(FavoriteEntry(board: board, threadNum: threadNum, title: title, addedAt: date))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    // MARK: - Post Drafts CRUD

    public func saveDraft(board: String, threadNum: Int, comment: String, name: String, email: String) {
        let sql = """
        INSERT OR REPLACE INTO drafts (board, thread_num, comment, name, email, updated_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            sqlite3_bind_text(statement, 3, (comment as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (email as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    public func getDraft(board: String, threadNum: Int) -> DraftEntry? {
        let sql = "SELECT comment, name, email, updated_at FROM drafts WHERE board = ? AND thread_num = ? LIMIT 1;"
        var statement: OpaquePointer?
        var result: DraftEntry? = nil

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))

            if sqlite3_step(statement) == SQLITE_ROW {
                if let commentPtr = sqlite3_column_text(statement, 0),
                   let namePtr = sqlite3_column_text(statement, 1),
                   let emailPtr = sqlite3_column_text(statement, 2) {
                    let comment = String(cString: commentPtr)
                    let name = String(cString: namePtr)
                    let email = String(cString: emailPtr)
                    let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                    result = DraftEntry(board: board, threadNum: threadNum, comment: comment, name: name, email: email, updatedAt: date)
                }
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    public func deleteDraft(board: String, threadNum: Int) {
        let sql = "DELETE FROM drafts WHERE board = ? AND thread_num = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (board as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(threadNum))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
}
