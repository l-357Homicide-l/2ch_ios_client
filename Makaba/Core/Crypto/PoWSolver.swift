//
//  PoWSolver.swift
//  Makaba
//
//  Production Apple CryptoKit SHA-512 Proof of Work solver for 2ch.org.
//

import Foundation
import CryptoKit

/// Errors encountered during Proof of Work resolution.
public enum PoWError: Error, LocalizedError, Equatable {
    case invalidTemplate
    case invalidTargetHash
    case limitExceeded(Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            return "Challenge template missing '%d' substitution marker or contains multiple markers."
        case .invalidTargetHash:
            return "Target SHA-512 digest must be a valid 128-character hexadecimal string."
        case .limitExceeded(let limit):
            return "Exceeded maximum iteration limit of \(limit) without hash match."
        case .cancelled:
            return "Proof of work calculation was cancelled."
        }
    }
}

/// The verified solution output from solving a PoW challenge.
public struct PoWResult: Equatable, Sendable {
    public let nonce: Int
    public let hash: String
    public let durationMs: Double

    public init(nonce: Int, hash: String, durationMs: Double) {
        self.nonce = nonce
        self.hash = hash
        self.durationMs = durationMs
    }
}

/// High-performance Proof of Work solver computing SHA-512 hashes using Apple's CryptoKit.
public final class PoWSolver: Sendable {

    /// Solves the Makaba SHA-512 Proof of Work challenge synchronously.
    ///
    /// - Parameters:
    ///   - template: Format string containing exactly one '%d' token.
    ///   - targetHash: 128-character lowercase hexadecimal target SHA-512 string.
    ///   - limit: Maximum iterations to probe (default 20,000, half-open interval `[0, limit)`).
    /// - Returns: A `PoWResult` containing the discovered nonce, matching hex hash, and elapsed time in ms.
    /// - Throws: `PoWError` if template is invalid, limit is exceeded, or negative limit is supplied.
    public static func solve(template: String, targetHash: String, limit: Int = 20000) throws -> PoWResult {
        // Challenger 2 Hardening: Guard against negative or zero limit
        guard limit > 0 else {
            throw PoWError.limitExceeded(limit)
        }

        // Validate template has exactly one '%d' substitution marker
        guard template.contains("%d") else {
            throw PoWError.invalidTemplate
        }

        let parts = template.components(separatedBy: "%d")
        guard parts.count == 2 else {
            throw PoWError.invalidTemplate
        }

        let prefix = parts[0]
        let suffix = parts[1]

        // Challenger 2 Hardening: Trim whitespace and lowercase target hash
        let normalizedTarget = targetHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedTarget.count == 128, let targetBytes = hexToBytes(normalizedTarget) else {
            throw PoWError.invalidTargetHash
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Iterate over strictly half-open interval [0, limit)
        for nonce in 0..<limit {
            let candidate = "\(prefix)\(nonce)\(suffix)"
            guard let data = candidate.data(using: .utf8) else { continue }

            let digest = SHA512.hash(data: data)

            // Direct byte-level comparison to avoid 20,000 intermediate string allocations
            if digest.elementsEqual(targetBytes) {
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                let hexString = digest.map { String(format: "%02x", $0) }.joined()
                return PoWResult(nonce: nonce, hash: hexString, durationMs: durationMs)
            }
        }

        throw PoWError.limitExceeded(limit)
    }

    /// Solves the Makaba SHA-512 Proof of Work challenge asynchronously on a background cooperative task.
    ///
    /// - Parameters:
    ///   - template: Format string containing '%d'.
    ///   - targetHash: 128-character hexadecimal target SHA-512 string.
    ///   - limit: Maximum iterations to probe.
    /// - Returns: A `PoWResult` containing the discovered nonce, matching hex hash, and elapsed time in ms.
    public static func solveAsync(template: String, targetHash: String, limit: Int = 20000) async throws -> PoWResult {
        return try await Task.detached(priority: .userInitiated) {
            // Check cancellation before heavy loop
            try Task.checkCancellation()

            guard limit > 0 else {
                throw PoWError.limitExceeded(limit)
            }

            guard template.contains("%d") else {
                throw PoWError.invalidTemplate
            }

            let parts = template.components(separatedBy: "%d")
            guard parts.count == 2 else {
                throw PoWError.invalidTemplate
            }

            let prefix = parts[0]
            let suffix = parts[1]

            let normalizedTarget = targetHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalizedTarget.count == 128, let targetBytes = hexToBytes(normalizedTarget) else {
                throw PoWError.invalidTargetHash
            }

            let startTime = CFAbsoluteTimeGetCurrent()

            for nonce in 0..<limit {
                // Cooperative cancellation check every 1024 iterations
                if (nonce & 1023) == 0 {
                    try Task.checkCancellation()
                }

                let candidate = "\(prefix)\(nonce)\(suffix)"
                guard let data = candidate.data(using: .utf8) else { continue }

                let digest = SHA512.hash(data: data)

                if digest.elementsEqual(targetBytes) {
                    let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    let hexString = digest.map { String(format: "%02x", $0) }.joined()
                    return PoWResult(nonce: nonce, hash: hexString, durationMs: durationMs)
                }
            }

            throw PoWError.limitExceeded(limit)
        }.value
    }

    // MARK: - Private Helpers

    /// Converts a 128-character hexadecimal string into 64 raw bytes.
    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count == 128 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(64)

        var index = hex.startIndex
        for _ in 0..<64 {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteSubstr = hex[index..<nextIndex]
            guard let byte = UInt8(byteSubstr, radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }
}
