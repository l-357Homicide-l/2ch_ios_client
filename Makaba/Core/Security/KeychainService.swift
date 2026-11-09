//
//  KeychainService.swift
//  Makaba
//
//  Thread-safe Keychain wrapper for securely storing sensitive credentials (e.g. 2ch VIP passcode).
//

import Foundation
import Security

public enum KeychainService {
    private static let serviceName = "org.2ch.Makaba.passcode"
    private static let accountName = "vip_token"
    private static let lock = NSLock()

    /// Persists the VIP passcode in the Keychain with device-only post-first-unlock protection.
    @discardableResult
    public static func savePasscode(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        lock.lock()
        defer { lock.unlock() }

        // 1. Delete query strictly restricted to identity attributes (prevents errSecParam -50)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 2. Add query with full payload and accessibility parameters
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads the stored VIP passcode from Keychain, or returns nil if absent.
    public static func loadPasscode() -> String? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored VIP passcode from Keychain.
    @discardableResult
    public static func deletePasscode() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
