//
//  Captcha.swift
//  Makaba
//
//  Models for 2ch.org Captcha and Proof of Work verification protocols.
//

import Foundation

/// Captcha requirement and session status codes.
public enum CaptchaStatus: Int, Codable, Sendable {
    case vipFail = 0
    case required = 1
    case vip = 2
    case disabled = 3
    case timeout = 4
    case banned = -6
    case unknown = -999

    public static func from(result: Int, hasBan: Bool) -> CaptchaStatus {
        if hasBan {
            return .banned
        }
        switch result {
        case 0: return .vipFail
        case 1: return .required
        case 2: return .vip
        case 3: return .disabled
        case -1, 4: return .timeout
        default: return .unknown
        }
    }
}

/// The Proof of Work cryptographic challenge parameters delivered by Makaba.
public struct PoWChallenge: Codable, Hashable, Sendable {
    public let hash: String
    public let limit: Int
    public let template: String

    public init(hash: String, limit: Int = 20000, template: String) {
        self.hash = hash
        self.limit = limit
        self.template = template
    }
}

/// Response returned from `/api/captcha/emoji/id`.
public struct CaptchaChallengeResponse: Codable, Sendable {
    public let result: Int
    public let type: String?
    public let input: String?
    public let id: String?
    public let challenge: PoWChallenge?
    public let maxFiles: Int?
    public let maxFilesSize: Int?
    public let warning: String?
    public let banned: String?

    enum CodingKeys: String, CodingKey {
        case result
        case type
        case input
        case id
        case challenge
        case maxFiles
        case maxFilesSize
        case warning
        case banned
    }

    public init(
        result: Int,
        type: String? = "emoji",
        input: String? = "emoji",
        id: String? = nil,
        challenge: PoWChallenge? = nil,
        maxFiles: Int? = 4,
        maxFilesSize: Int? = 20480,
        warning: String? = nil,
        banned: String? = nil
    ) {
        self.result = result
        self.type = type
        self.input = input
        self.id = id
        self.challenge = challenge
        self.maxFiles = maxFiles
        self.maxFilesSize = maxFilesSize
        self.warning = warning
        self.banned = banned
    }

    public var status: CaptchaStatus {
        return CaptchaStatus.from(result: result, hasBan: banned != nil)
    }

    /// Whether user holds valid VIP passcode bypass.
    public var isVIPBypass: Bool {
        return result == 2
    }

    /// Whether captcha is disabled on this board/thread.
    public var isCaptchaDisabled: Bool {
        return result == 3
    }

    /// Whether full verification (PoW + Emoji) is mandated.
    public var isVerificationRequired: Bool {
        return result == 1 && challenge != nil && id != nil
    }
}

/// Visual puzzle payload returned from `/api/captcha/emoji/show`.
public struct CaptchaShowResponse: Codable, Sendable {
    /// Base64-encoded PNG image displaying the challenge target symbols.
    public let image: String
    /// Array of exactly 8 Base64-encoded PNG icon buttons for user selection.
    public let keyboard: [String]

    public init(image: String, keyboard: [String]) {
        self.image = image
        self.keyboard = keyboard
    }

    /// Helper converting Base64 prompt image to raw Data.
    public var imageData: Data? {
        return Data(base64Encoded: image)
    }

    /// Helper converting Base64 keyboard button images to raw Data.
    public var keyboardData: [Data] {
        return keyboard.compactMap { Data(base64Encoded: $0) }
    }
}

/// Request payload submitted to `POST /api/captcha/emoji/click`.
public struct CaptchaClickRequest: Codable, Sendable {
    public let captchaTokenID: String
    public let emojiNumber: Int

    public init(captchaTokenID: String, emojiNumber: Int) {
        self.captchaTokenID = captchaTokenID
        self.emojiNumber = emojiNumber
    }
}

/// Response returned from `POST /api/captcha/emoji/click`.
/// May contain either another round of prompt+keyboard or terminal `success` token.
public struct CaptchaClickResponse: Codable, Sendable {
    public let image: String?
    public let keyboard: [String]?
    public let success: String?

    public init(image: String? = nil, keyboard: [String]? = nil, success: String? = nil) {
        self.image = image
        self.keyboard = keyboard
        self.success = success
    }

    /// Whether the user successfully completed the verification puzzle.
    public var isSuccess: Bool {
        return success != nil
    }

    /// The verified token to submit in posting form as `emoji_captcha_id`.
    public var verifiedToken: String? {
        return success
    }

    /// Whether another emoji selection round is required.
    public var hasMoreRounds: Bool {
        return image != nil && keyboard != nil && success == nil
    }
}

// MARK: - Interface Contract Typealiases (PROJECT.md)
public typealias CaptchaChallenge = CaptchaChallengeResponse
public typealias CaptchaImages = CaptchaShowResponse
public typealias CaptchaClickResult = CaptchaClickResponse

