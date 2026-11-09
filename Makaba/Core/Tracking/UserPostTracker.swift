//
//  UserPostTracker.swift
//  Makaba
//
//  Local user post tracking delivering (Вы) and (Вам) author feedback badges.
//

import SwiftUI

/// Tracks posts authored by the local user to render (Вы) and quote notification (Вам) indicators.
public final class UserPostTracker: @unchecked Sendable {
    public static let shared = UserPostTracker()

    private let lock = NSLock()
    private var ownPostsByBoard: [String: Set<Int>] = [:]
    private let storageKey = "MakabaUserTrackedPosts"

    private init() {
        loadFromStorage()
    }

    private func loadFromStorage() {
        lock.lock()
        defer { lock.unlock() }
        if let rawDict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [Int]] {
            self.ownPostsByBoard = rawDict.mapValues { Set($0) }
        }
    }

    private func saveToStorage() {
        let exportDict = ownPostsByBoard.mapValues { Array($0) }
        UserDefaults.standard.set(exportDict, forKey: storageKey)
    }

    /// Records a newly submitted post number under the target board.
    public func recordOwnPost(board: String, num: Int) {
        lock.lock()
        defer { lock.unlock() }
        let key = board.lowercased()
        var current = ownPostsByBoard[key] ?? []
        current.insert(num)
        ownPostsByBoard[key] = current
        saveToStorage()
    }

    /// Whether this post was authored by the user on this device.
    public func isOwnPost(board: String, num: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = board.lowercased()
        return ownPostsByBoard[key]?.contains(num) ?? false
    }

    /// Whether this post quotes any post authored by the local user in the specified board.
    public func isQuotingUser(board: String, post: Post) -> Bool {
        lock.lock()
        let ownSet = ownPostsByBoard[board.lowercased()] ?? []
        lock.unlock()

        guard !ownSet.isEmpty else { return false }

        // Inspect comment HTML for >>NUMBER quote links
        for ownNum in ownSet {
            let quotePattern = ">>\(ownNum)"
            let linkPattern = "data-num=\"\(ownNum)\""
            if post.comment.contains(quotePattern) || post.comment.contains(linkPattern) {
                return true
            }
        }
        return false
    }
}

/// SwiftUI visual badge displaying (Вы) or (Вам) indicator in post headers.
public struct UserPostBadgeView: View {
    public let isOwn: Bool
    public let isQuotingYou: Bool

    public init(isOwn: Bool, isQuotingYou: Bool) {
        self.isOwn = isOwn
        self.isQuotingYou = isQuotingYou
    }

    public var body: some View {
        HStack(spacing: 4) {
            if isOwn {
                Text("(Вы)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green))
            } else if isQuotingYou {
                Text("(Вам)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan))
            }
        }
    }
}
