//
//  PostingResult.swift
//  Makaba
//
//  Posting result decoding, error structures, and upload payload definitions.
//

import Foundation

/// Detailed server error returned upon failed post submission.
public struct PostingErrorDetail: Codable, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// Response returned from `POST https://2ch.org/user/posting`.
public struct PostingResponse: Codable, Sendable {
    public let result: Int
    public let num: Int?
    public let thread: Int?
    public let error: PostingErrorDetail?

    public init(result: Int, num: Int? = nil, thread: Int? = nil, error: PostingErrorDetail? = nil) {
        self.result = result
        self.num = num
        self.thread = thread
        self.error = error
    }

    /// Whether the post or thread was created successfully.
    public var isSuccess: Bool {
        return result == 1
    }

    /// The resulting post number (if reply) or thread number (if new thread).
    public var targetID: Int? {
        return num ?? thread
    }

    /// User-facing error message, if any.
    public var errorMessage: String? {
        return error?.message
    }
}

/// A media file attachment prepared for multipart upload.
public struct PostFileAttachment: Sendable {
    public let fileName: String
    public let mimeType: String
    public let data: Data

    public init(fileName: String, mimeType: String, data: Data) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

/// Client payload defining all fields submitted when replying or creating a thread.
public struct PostPayload: Sendable {
    public let task: String
    public let board: String
    public let thread: Int // 0 when creating a new thread
    public let comment: String?
    public let challenge: String? // 2ch_challenge (PoW solution nonce)
    public let captchaType: String? // captcha_type ("emoji_captcha", "passcode", "nocaptcha")
    public let emojiCaptchaID: String? // emoji_captcha_id (verified token)
    public let usercode: String? // Passcode VIP token
    public let email: String?
    public let sage: Bool
    public let subject: String?
    public let name: String?
    public let opMark: Bool
    public let tags: String?
    public let icon: Int?
    public let files: [PostFileAttachment]

    public init(
        board: String,
        thread: Int = 0,
        comment: String? = nil,
        challenge: String? = nil,
        captchaType: String? = "emoji_captcha",
        emojiCaptchaID: String? = nil,
        usercode: String? = nil,
        email: String? = nil,
        sage: Bool = false,
        subject: String? = nil,
        name: String? = nil,
        opMark: Bool = false,
        tags: String? = nil,
        icon: Int? = nil,
        files: [PostFileAttachment] = []
    ) {
        self.task = "post"
        self.board = board
        self.thread = thread
        self.comment = comment
        self.challenge = challenge
        self.captchaType = captchaType
        self.emojiCaptchaID = emojiCaptchaID
        self.usercode = usercode
        self.email = email
        self.sage = sage
        self.subject = subject
        self.name = name
        self.opMark = opMark
        self.tags = tags
        self.icon = icon
        self.files = files
    }

    /// Whether this payload is creating a new thread (thread == 0).
    public var isNewThread: Bool {
        return thread == 0
    }
}

// MARK: - Interface Contract Typealiases (PROJECT.md)
public typealias PostResult = PostingResponse

