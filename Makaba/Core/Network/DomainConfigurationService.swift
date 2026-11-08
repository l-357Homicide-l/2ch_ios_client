//
//  DomainConfigurationService.swift
//  Makaba
//
//  Dynamic mirror configuration and automated failover service.
//  Provides seamless failover across 2ch.hk, 2ch.org, 2ch.pm, 2ch.re, and 2ch.life.
//

import Foundation
import Combine

extension Notification.Name {
    public static let makabaDomainDidChange = Notification.Name("MakabaDomainDidChangeNotification")
}

public final class DomainConfigurationService: ObservableObject, @unchecked Sendable {
    public static let shared = DomainConfigurationService()

    /// Default production fallback domain.
    public static let defaultDomain: String = "https://2ch.org"

    /// Supported official and community mirror endpoints ordered by preference.
    public static let availableMirrors: [String] = [
        "https://2ch.org",
        "https://2ch.hk",
        "https://2ch.pm",
        "https://2ch.re",
        "https://2ch.life"
    ]

    private let userDefaultsKey = "selected_domain"
    private let lock = NSLock()
    private var _domain: String

    @Published public private(set) var activeDomain: String

    private init() {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)
        let initial = (stored != nil && Self.availableMirrors.contains(stored!)) ? stored! : Self.defaultDomain
        self._domain = initial
        self.activeDomain = initial
    }

    /// The base URL currently selected for network operations.
    public var baseURL: URL {
        lock.lock()
        defer { lock.unlock() }
        return URL(string: _domain) ?? URL(string: Self.defaultDomain)!
    }

    /// Raw active domain string (e.g., "https://2ch.hk").
    public var currentDomain: String {
        lock.lock()
        defer { lock.unlock() }
        return _domain
    }

    /// Stripped hostname without scheme for display in UI (e.g., "2ch.hk").
    public var activeHost: String {
        return baseURL.host ?? "2ch"
    }

    /// Sets the active domain explicitly (e.g. from user settings or auto-selector).
    public func setDomain(_ newDomain: String) {
        lock.lock()
        let clean = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = clean.hasPrefix("http") ? clean : "https://\(clean)"
        guard _domain != normalized else {
            lock.unlock()
            return
        }
        _domain = normalized
        UserDefaults.standard.set(normalized, forKey: userDefaultsKey)
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.activeDomain = normalized
            NotificationCenter.default.post(
                name: .makabaDomainDidChange,
                object: normalized
            )
        }
    }

    /// Cycles automatically to the next configured mirror upon connection failure or DNS block.
    @discardableResult
    public func failoverToNextMirror() -> String {
        lock.lock()
        let current = _domain
        let currentIndex = Self.availableMirrors.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + 1) % Self.availableMirrors.count
        let nextMirror = Self.availableMirrors[nextIndex]
        _domain = nextMirror
        UserDefaults.standard.set(nextMirror, forKey: userDefaultsKey)
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.activeDomain = nextMirror
            NotificationCenter.default.post(
                name: .makabaDomainDidChange,
                object: nextMirror
            )
        }
        return nextMirror
    }

    /// Resolves a full URL for relative paths against the currently active mirror.
    public func buildURL(path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        let base = currentDomain
        return URL(string: "\(base)\(cleanPath)")
    }

    /// Rewrites an existing URL to target the active mirror or a specified mirror.
    public func rewriteURL(_ url: URL?, to targetDomain: String? = nil) -> URL? {
        guard let url = url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        let target = targetDomain ?? currentDomain
        if let targetComponents = URLComponents(string: target) {
            components.scheme = targetComponents.scheme
            components.host = targetComponents.host
            components.port = targetComponents.port
        }
        return components.url
    }

    /// Measures connection latency to a given mirror in seconds. Returns nil on timeout or error.
    public func ping(mirror: String, timeout: TimeInterval = 3.0) async -> TimeInterval? {
        guard let url = URL(string: "\(mirror)/api/mobile/v2/boards") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                return CFAbsoluteTimeGetCurrent() - start
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Pings all configured mirrors concurrently and returns latency benchmarks.
    public func testAllMirrors() async -> [String: TimeInterval?] {
        await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for mirror in Self.availableMirrors {
                group.addTask {
                    let latency = await self.ping(mirror: mirror)
                    return (mirror, latency)
                }
            }
            var results: [String: TimeInterval?] = [:]
            for await (mirror, latency) in group {
                results[mirror] = latency
            }
            return results
        }
    }

    /// Automatically selects and sets the mirror with the lowest measured latency.
    @discardableResult
    public func autoSelectFastestMirror() async -> String {
        let results = await testAllMirrors()
        let sorted = results.compactMap { key, value -> (String, TimeInterval)? in
            guard let v = value else { return nil }
            return (key, v)
        }.sorted { $0.1 < $1.1 }

        if let fastest = sorted.first?.0 {
            setDomain(fastest)
            return fastest
        }
        return currentDomain
    }
}
