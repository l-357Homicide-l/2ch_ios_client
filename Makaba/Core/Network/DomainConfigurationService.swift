//
//  DomainConfigurationService.swift
//  Makaba
//
//  Dynamic mirror configuration, content-validating health checks, and automated failover service.
//  Provides seamless failover across verified mirrors (2ch.org, 2ch.hk), user custom mirrors,
//  and unverified fallbacks (2ch.pm, 2ch.life), with strict JSON payload validation.
//

import Foundation
import Combine

extension Notification.Name {
    public static let makabaDomainDidChange = Notification.Name("MakabaDomainDidChangeNotification")
    public static let makabaPasscodeDidChange = Notification.Name("MakabaPasscodeDidChangeNotification")
}

public final class DomainConfigurationService: ObservableObject, @unchecked Sendable {
    public static let shared = DomainConfigurationService()

    /// Default production fallback domain.
    public static let defaultDomain: String = "https://2ch.org"

    /// Verified production mirrors serving full Makaba JSON API.
    public static let verifiedMirrors: [String] = [
        "https://2ch.org",
        "https://2ch.hk"
    ]

    /// Unverified/experimental fallbacks (e.g. Cloudflare captcha or HTML blocks).
    /// Kept out of automated failover until explicitly activated or verified.
    public static let fallbackMirrors: [String] = [
        "https://2ch.pm",
        "https://2ch.life"
    ]

    /// All pre-configured and custom mirrors.
    public static var availableMirrors: [String] {
        return shared.allMirrors
    }

    private let userDefaultsKey = "selected_domain"
    private let customMirrorsKey = "custom_mirrors"
    private let passcodeKey = "makaba_passcode_token"
    private let lock = NSRecursiveLock()
    private var _domain: String
    private var internalCustomMirrors: [String]
    private var internalPasscodeToken: String?

    @Published public private(set) var activeDomain: String
    @Published public private(set) var customMirrors: [String]
    @Published public private(set) var passcodeToken: String?

    private init() {
        let storedDomain = UserDefaults.standard.string(forKey: userDefaultsKey)
        let storedCustom = UserDefaults.standard.stringArray(forKey: customMirrorsKey) ?? []
        let storedPasscode = UserDefaults.standard.string(forKey: passcodeKey)

        self.internalCustomMirrors = storedCustom
        self.customMirrors = storedCustom
        self.internalPasscodeToken = storedPasscode
        self.passcodeToken = storedPasscode

        let allValid = Self.verifiedMirrors + storedCustom + Self.fallbackMirrors
        let initial = (storedDomain != nil && allValid.contains(storedDomain!)) ? storedDomain! : Self.defaultDomain
        self._domain = initial
        self.activeDomain = initial
    }

    /// Combined list of all verified, user custom, and fallback mirrors.
    public var allMirrors: [String] {
        lock.lock()
        defer { lock.unlock() }
        var list = Self.verifiedMirrors + internalCustomMirrors
        for fallback in Self.fallbackMirrors {
            if !list.contains(fallback) {
                list.append(fallback)
            }
        }
        return list
    }

    /// Mirrors eligible for automated failover and fastest-mirror selection.
    /// Excludes unverified fallbacks to prevent Cloudflare HTML challenge loops.
    public var autoFailoverMirrors: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Self.verifiedMirrors + internalCustomMirrors
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
        self.activeDomain = normalized
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .makabaDomainDidChange,
                object: normalized
            )
        }
    }

    /// Adds a user-defined custom mirror (e.g. personal proxy or new 2ch mirror).
    @discardableResult
    public func addCustomMirror(_ rawDomain: String) -> (success: Bool, message: String) {
        let clean = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return (false, "Домен не может быть пустым.")
        }
        let normalized = clean.hasPrefix("http") ? clean : "https://\(clean)"
        guard let url = URL(string: normalized), url.host != nil else {
            return (false, "Некорректный URL зеркала.")
        }

        lock.lock()
        if !internalCustomMirrors.contains(normalized) && !Self.verifiedMirrors.contains(normalized) && !Self.fallbackMirrors.contains(normalized) {
            internalCustomMirrors.append(normalized)
            UserDefaults.standard.set(internalCustomMirrors, forKey: customMirrorsKey)
        }
        let updated = internalCustomMirrors
        self.customMirrors = updated
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .makabaDomainDidChange,
                object: normalized
            )
        }
        return (true, "Зеркало добавлено.")
    }

    /// Removes a custom mirror.
    public func removeCustomMirror(_ mirror: String) {
        lock.lock()
        internalCustomMirrors.removeAll { $0 == mirror }
        UserDefaults.standard.set(internalCustomMirrors, forKey: customMirrorsKey)
        let updated = internalCustomMirrors
        self.customMirrors = updated
        let isCurrent = (_domain == mirror)
        lock.unlock()

        if isCurrent {
            setDomain(Self.defaultDomain)
        }
    }

    /// Updates or clears the 2ch passcode token.
    public func setPasscode(_ token: String?) {
        let clean = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalToken = (clean?.isEmpty ?? true) ? nil : clean

        lock.lock()
        internalPasscodeToken = finalToken
        if let t = finalToken {
            UserDefaults.standard.set(t, forKey: passcodeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: passcodeKey)
        }
        self.passcodeToken = finalToken
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .makabaPasscodeDidChange,
                object: finalToken
            )
        }
    }

    /// Cycles automatically to the next configured verified mirror upon connection failure or DNS block.
    @discardableResult
    public func failoverToNextMirror() -> String {
        lock.lock()
        let pool = (Self.verifiedMirrors + internalCustomMirrors).isEmpty ? (Self.verifiedMirrors + internalCustomMirrors + Self.fallbackMirrors) : (Self.verifiedMirrors + internalCustomMirrors)
        let current = _domain
        let currentIndex = pool.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + 1) % pool.count
        let nextMirror = pool[nextIndex]
        _domain = nextMirror
        UserDefaults.standard.set(nextMirror, forKey: userDefaultsKey)
        self.activeDomain = nextMirror
        lock.unlock()

        DispatchQueue.main.async {
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

    /// Rigorous content-validating health-check.
    /// Probes the lightweight 461-byte captcha ID endpoint and validates HTTP 200, Content-Type: application/json,
    /// and successful JSON deserialization. Returns latency in seconds, or nil if Cloudflare block/HTML/error.
    public func ping(mirror: String, timeout: TimeInterval = 4.0) async -> TimeInterval? {
        guard let url = URL(string: "\(mirror)/api/captcha/emoji/id?board=b&thread=0") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            // Strict Content-Type validation: reject HTML challenges or parking pages
            guard let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                  contentType.contains("application/json") else {
                return nil
            }
            // Valid JSON dictionary validation: must deserialize into valid Makaba response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  !json.isEmpty else {
                return nil
            }
            return CFAbsoluteTimeGetCurrent() - start
        } catch {
            return nil
        }
    }

    /// Probes all verified and custom mirrors concurrently and returns latency benchmarks.
    public func testAllMirrors() async -> [String: TimeInterval?] {
        let targets = autoFailoverMirrors
        return await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for mirror in targets {
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

    /// Automatically selects and sets the mirror with the lowest measured latency that passed JSON content validation.
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
