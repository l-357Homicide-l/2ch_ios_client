//
//  WipeShieldService.swift
//  Makaba
//
//  Client-side anti-spam and content filtering engine protecting against wipe flood campaigns.
//

import Foundation

public enum FilterAction: Sendable {
    case pass
    case collapsed(reason: String)
    case hidden(reason: String)
}

/// Thread-safe client-side content filter for posts and flood protection.
public final class WipeShieldService: @unchecked Sendable {
    public static let shared = WipeShieldService()

    private let lock = NSLock()
    private var blacklistedKeywords: Set<String> = []
    private var blacklistedTripcodes: Set<String> = []

    private let keywordsKey = "MakabaFilterKeywords"
    private let tripsKey = "MakabaFilterTripcodes"

    private init() {
        loadRules()
    }

    private func loadRules() {
        lock.lock()
        defer { lock.unlock() }

        if let kw = UserDefaults.standard.array(forKey: keywordsKey) as? [String] {
            self.blacklistedKeywords = Set(kw.map { $0.lowercased() })
        }
        if let trips = UserDefaults.standard.array(forKey: tripsKey) as? [String] {
            self.blacklistedTripcodes = Set(trips)
        }
    }

    private func saveRules() {
        UserDefaults.standard.set(Array(blacklistedKeywords), forKey: keywordsKey)
        UserDefaults.standard.set(Array(blacklistedTripcodes), forKey: tripsKey)
    }

    public func addKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        lock.lock()
        blacklistedKeywords.insert(trimmed)
        saveRules()
        lock.unlock()
    }

    public func removeKeyword(_ keyword: String) {
        lock.lock()
        blacklistedKeywords.remove(keyword.lowercased())
        saveRules()
        lock.unlock()
    }

    public func getKeywords() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(blacklistedKeywords).sorted()
    }

    public func addTripcode(_ trip: String) {
        let trimmed = trip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        blacklistedTripcodes.insert(trimmed)
        saveRules()
        lock.unlock()
    }

    public func removeTripcode(_ trip: String) {
        lock.lock()
        blacklistedTripcodes.remove(trip)
        saveRules()
        lock.unlock()
    }

    public func getTripcodes() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(blacklistedTripcodes).sorted()
    }

    /// Linear O(N) non-backtracking scanner detecting identical consecutive character floods.
    private func hasExcessiveCharacterRepetition(_ text: String, threshold: Int = 12) -> Bool {
        var count = 0
        var lastChar: Character?
        for char in text {
            if char == lastChar {
                count += 1
                if count >= threshold { return true }
            } else {
                lastChar = char
                count = 1
            }
        }
        return false
    }

    /// Evaluates a post against all configured spam and content filter rules.
    public func evaluate(post: Post) -> FilterAction {
        lock.lock()
        let keywords = blacklistedKeywords
        let tripcodes = blacklistedTripcodes
        lock.unlock()

        // 1. Tripcode blacklist check
        if let postTrip = post.trip, !postTrip.isEmpty, tripcodes.contains(postTrip) {
            return .hidden(reason: "Заблокированный трипкод \(postTrip)")
        }

        // 2. Keyword check against plain comment text and subject (ignoring HTML tags)
        let plainText = MakabaHTMLParser.toPlainText(html: post.comment).lowercased()
        let lowerSubject = (post.subject ?? "").lowercased()

        for kw in keywords {
            if plainText.contains(kw) || lowerSubject.contains(kw) {
                return .collapsed(reason: "Фильтр ключевых слов: '\(kw)'")
            }
        }

        // 3. Flood repetition heuristic (>12 consecutive identical characters)
        if hasExcessiveCharacterRepetition(plainText, threshold: 12) {
            return .collapsed(reason: "Вайп-флуд: повторяющиеся символы")
        }

        return .pass
    }
}
