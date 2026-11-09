//
//  ThreadWatchService.swift
//  Makaba
//
//  Background thread watch service monitoring favorited threads for incoming replies.
//

import Foundation
import UserNotifications

public struct WatchedThread: Codable, Identifiable, Sendable {
    public var id: String { "\(board)_\(threadNum)" }
    public let board: String
    public let threadNum: Int
    public var title: String
    public var lastSeenPostNum: Int
    public var unreadCount: Int
    public var lastCheckedAt: Date
}

public actor ThreadWatchService {
    public static let shared = ThreadWatchService()

    private var watchedThreads: [String: WatchedThread] = [:]
    private let storageKey = "MakabaWatchedThreads"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: WatchedThread].self, from: data) {
            self.watchedThreads = decoded
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(watchedThreads) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    /// Adds or updates a thread in the watchlist.
    public func watchThread(board: String, threadNum: Int, title: String, currentLastNum: Int) {
        let key = "\(board.lowercased())_\(threadNum)"
        let entry = WatchedThread(
            board: board,
            threadNum: threadNum,
            title: title,
            lastSeenPostNum: currentLastNum,
            unreadCount: 0,
            lastCheckedAt: Date()
        )
        watchedThreads[key] = entry
        persist()
    }

    public func unwatchThread(board: String, threadNum: Int) {
        let key = "\(board.lowercased())_\(threadNum)"
        watchedThreads.removeValue(forKey: key)
        persist()
    }

    public func isWatched(board: String, threadNum: Int) -> Bool {
        let key = "\(board.lowercased())_\(threadNum)"
        return watchedThreads[key] != nil
    }

    public func getWatchedThreads() -> [WatchedThread] {
        return Array(watchedThreads.values).sorted { $0.lastCheckedAt > $1.lastCheckedAt }
    }

    /// Polls all watched threads for new incoming posts using delta /after endpoint.
    public func refreshAllWatchedThreads() async -> Int {
        var totalNewReplies = 0

        for (key, var thread) in watchedThreads {
            do {
                let response = try await MakabaAPIClient.shared.fetchThreadAfter(
                    board: thread.board,
                    thread: thread.threadNum,
                    after: thread.lastSeenPostNum
                )

                let newPosts = response.posts.filter { $0.num > thread.lastSeenPostNum }
                if !newPosts.isEmpty {
                    thread.unreadCount += newPosts.count
                    if let highestNum = newPosts.map(\.num).max() {
                        thread.lastSeenPostNum = highestNum
                    }
                    totalNewReplies += newPosts.count
                    sendNotification(for: thread, newCount: newPosts.count)
                }

                thread.lastCheckedAt = Date()
                watchedThreads[key] = thread
            } catch {
                continue
            }
        }

        persist()
        return totalNewReplies
    }

    private func sendNotification(for thread: WatchedThread, newCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "/\(thread.board)/ — Новые ответы"
        content.body = "В треде #\(thread.threadNum) (\(thread.title.prefix(30))) появилось \(newCount) новых сообщений."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "thread_\(thread.board)_\(thread.threadNum)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }
}
