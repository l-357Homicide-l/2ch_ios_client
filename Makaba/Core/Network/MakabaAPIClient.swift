//
//  MakabaAPIClient.swift
//  Makaba
//
//  Production async/await URLSession client covering all 2ch.org API endpoints.
//

import Foundation

// MARK: - Interface Contract Typealiases (PROJECT.md)
public typealias CaptchaChallenge = CaptchaChallengeResponse
public typealias CaptchaImages = CaptchaShowResponse
public typealias CaptchaClickResult = CaptchaClickResponse
public typealias PostResult = PostingResponse

/// Specific errors thrown by the Makaba API client.
public enum MakabaAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decodingError(String)
    case serverError(code: Int, message: String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The requested URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid or unrecognized HTTP response."
        case .httpError(let statusCode, _):
            return "HTTP Error \(statusCode)."
        case .decodingError(let detail):
            return "Failed to decode response JSON: \(detail)"
        case .serverError(let code, let message):
            return "Makaba API error [\(code)]: \(message)"
        case .networkError(let detail):
            return "Network connection error: \(detail)"
        }
    }
}

/// Actor or class implementing full async/await networking for the Makaba imageboard engine.
public final class MakabaAPIClient: Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let passcodeToken: String?

    public init(
        baseURL: URL = MakabaEndpoint.defaultBaseURL,
        session: URLSession? = nil,
        passcodeToken: String? = nil
    ) {
        self.baseURL = baseURL
        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            config.requestCachePolicy = .useProtocolCachePolicy
            self.session = URLSession(configuration: config)
        }
        self.passcodeToken = passcodeToken
    }

    // MARK: - Public Read Endpoints

    /// Fetches all active public boards on 2ch.org.
    public func fetchBoards() async throws -> [Board] {
        let req = MakabaEndpoint.boards.request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        let decoder = JSONDecoder()
        if let boards = try? decoder.decode([Board].self, from: data) {
            return boards
        }
        // Fallback for wrapped dictionary responses
        if let dict = try? decoder.decode([String: [Board]].self, from: data) {
            return dict.values.flatMap { $0 }
        }

        do {
            return try decoder.decode([Board].self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches and organizes all boards into category groups.
    public func fetchBoardCategories() async throws -> [BoardCategory] {
        let boards: [Board] = try await fetchBoards()
        return BoardCategory.groupByCategory(boards)
    }

    /// Overload resolving boards directly grouped into categories per PROJECT.md interface contract.
    public func fetchBoards() async throws -> [BoardCategory] {
        return try await fetchBoardCategories()
    }

    /// Fetches the catalog containing all active threads for a board.
    public func fetchCatalog(board: String) async throws -> CatalogResponse {
        let req = MakabaEndpoint.catalog(board: board).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(CatalogResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches the flat thread listing for a board.
    public func fetchThreadList(board: String) async throws -> ThreadListResponse {
        let req = MakabaEndpoint.threads(board: board).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(ThreadListResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches all posts in a thread given the board ID and thread root number.
    public func fetchThread(board: String, threadNum: Int) async throws -> ThreadResponse {
        let req = MakabaEndpoint.thread(board: board, threadNum: threadNum).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(ThreadResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches an archived thread history.
    public func fetchArchivedThread(board: String, threadNum: Int) async throws -> ThreadResponse {
        let req = MakabaEndpoint.archivedThread(board: board, threadNum: threadNum).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(ThreadResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Captcha & Verification Endpoints

    /// Fetches the JWE Captcha token and SHA-512 Proof of Work challenge.
    public func fetchCaptcha(board: String, thread: Int) async throws -> CaptchaChallengeResponse {
        let req = MakabaEndpoint.captchaID(board: board, thread: thread).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(CaptchaChallengeResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches the Emoji visual prompt image and 8 button icons.
    public func fetchCaptchaShow(id: String) async throws -> CaptchaShowResponse {
        let req = MakabaEndpoint.captchaShow(id: id).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(CaptchaShowResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches the Emoji visual prompt image and 8 button icons (PROJECT.md contract alias).
    public func fetchCaptchaImages(id: String) async throws -> CaptchaImages {
        return try await fetchCaptchaShow(id: id)
    }

    /// Submits the user's emoji button selection.
    public func submitCaptchaClick(tokenID: String, emojiNumber: Int) async throws -> CaptchaClickResponse {
        var req = MakabaEndpoint.captchaClick.request(baseURL: baseURL, passcodeToken: passcodeToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let clickPayload = CaptchaClickRequest(captchaTokenID: tokenID, emojiNumber: emojiNumber)
        req.httpBody = try JSONEncoder().encode(clickPayload)

        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            return try JSONDecoder().decode(CaptchaClickResponse.self, from: data)
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Posting & Voting Endpoints

    /// Submits a reply or creates a new thread using RFC 7578 multipart/form-data.
    public func submitPost(payload: PostPayload) async throws -> PostResult {
        var multipart = MultipartFormData()
        multipart.appendField(name: "task", value: payload.task)
        multipart.appendField(name: "board", value: payload.board)
        multipart.appendField(name: "thread", value: String(payload.thread))

        multipart.appendFieldIfPresent(name: "comment", value: payload.comment)
        multipart.appendFieldIfPresent(name: "2ch_challenge", value: payload.challenge)
        multipart.appendFieldIfPresent(name: "captcha_type", value: payload.captchaType)
        multipart.appendFieldIfPresent(name: "emoji_captcha_id", value: payload.emojiCaptchaID)
        multipart.appendFieldIfPresent(name: "usercode", value: payload.usercode)
        multipart.appendFieldIfPresent(name: "email", value: payload.email)

        if payload.sage {
            multipart.appendField(name: "sage", value: "1")
        }

        multipart.appendFieldIfPresent(name: "subject", value: payload.subject)
        multipart.appendFieldIfPresent(name: "name", value: payload.name)

        if payload.opMark {
            multipart.appendField(name: "op_mark", value: "1")
        }

        multipart.appendFieldIfPresent(name: "tags", value: payload.tags)

        if let icon = payload.icon {
            multipart.appendField(name: "icon", value: String(icon))
        }

        for file in payload.files {
            multipart.appendFile(
                name: "file[]",
                filename: file.fileName,
                mimeType: file.mimeType,
                data: file.data
            )
        }

        var req = MakabaEndpoint.posting.request(baseURL: baseURL, passcodeToken: passcodeToken)
        req.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = multipart.build()

        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)

        do {
            let postingResult = try JSONDecoder().decode(PostingResponse.self, from: data)
            if !postingResult.isSuccess, let err = postingResult.error {
                throw MakabaAPIError.serverError(code: err.code, message: err.message)
            }
            return postingResult
        } catch let apiErr as MakabaAPIError {
            throw apiErr
        } catch {
            throw MakabaAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Upvotes a post on boards where likes are enabled.
    public func likePost(board: String, num: Int) async throws -> Bool {
        let req = MakabaEndpoint.like(board: board, num: num).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)
        return true
    }

    /// Downvotes a post on boards where likes are enabled.
    public func dislikePost(board: String, num: Int) async throws -> Bool {
        let req = MakabaEndpoint.dislike(board: board, num: num).request(baseURL: baseURL, passcodeToken: passcodeToken)
        let (data, response) = try await execute(request: req)
        try validateHTTPStatus(response, data: data)
        return true
    }

    // MARK: - Internal Networking Helpers

    private func execute(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw MakabaAPIError.networkError(error.localizedDescription)
        }
    }

    private func validateHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MakabaAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MakabaAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }
}
