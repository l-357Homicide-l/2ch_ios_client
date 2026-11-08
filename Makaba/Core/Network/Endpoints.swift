//
//  Endpoints.swift
//  Makaba
//
//  Authoritative endpoint routing and URLRequest factory for 2ch.org (Makaba engine).
//

import Foundation

/// Defines all REST and media endpoints supported by the Makaba engine.
public enum MakabaEndpoint: Sendable {
    case boards
    case catalog(board: String)
    case threads(board: String)
    case boardPage(board: String, page: Int)
    case thread(board: String, threadNum: Int)
    case archivedThread(board: String, threadNum: Int)
    case captchaID(board: String, thread: Int)
    case captchaShow(id: String)
    case captchaClick
    case posting
    case like(board: String, num: Int)
    case dislike(board: String, num: Int)
    case media(path: String)
    case thumbnail(path: String)

    /// Base host domain for 2ch.org.
    public static var defaultBaseURL: URL {
        return URL(string: "https://2ch.org")!
    }

    /// Constructs the relative URL path for the endpoint.
    public var path: String {
        switch self {
        case .boards:
            return "/api/mobile/v2/boards"
        case .catalog(let board):
            return "/\(board)/catalog.json"
        case .threads(let board):
            return "/\(board)/threads.json"
        case .boardPage(let board, let page):
            let file = page == 0 ? "index.json" : "\(page).json"
            return "/\(board)/\(file)"
        case .thread(let board, let threadNum):
            return "/\(board)/res/\(threadNum).json"
        case .archivedThread(let board, let threadNum):
            return "/arch/\(board)/res/\(threadNum).json"
        case .captchaID:
            return "/api/captcha/emoji/id"
        case .captchaShow:
            return "/api/captcha/emoji/show"
        case .captchaClick:
            return "/api/captcha/emoji/click"
        case .posting:
            return "/user/posting"
        case .like:
            return "/api/like"
        case .dislike:
            return "/api/dislike"
        case .media(let path), .thumbnail(let path):
            return path.hasPrefix("/") ? path : "/\(path)"
        }
    }

    /// Query items appended to the URL.
    public var queryItems: [URLQueryItem]? {
        switch self {
        case .captchaID(let board, let thread):
            return [
                URLQueryItem(name: "board", value: board),
                URLQueryItem(name: "thread", value: String(thread))
            ]
        case .captchaShow(let id):
            return [
                URLQueryItem(name: "id", value: id)
            ]
        case .posting:
            return [
                URLQueryItem(name: "nc", value: "1")
            ]
        case .like(let board, let num), .dislike(let board, let num):
            return [
                URLQueryItem(name: "board", value: board),
                URLQueryItem(name: "num", value: String(num))
            ]
        default:
            return nil
        }
    }

    /// HTTP method used for the endpoint.
    public var httpMethod: String {
        switch self {
        case .captchaClick, .posting:
            return "POST"
        default:
            return "GET"
        }
    }

    /// Resolves the full URL using the given base host with robust percent-encoding for spaces and Cyrillic paths.
    public func url(baseURL: URL = defaultBaseURL) -> URL {
        let baseStr = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Safely percent-encode path segments containing spaces or non-ASCII characters
        let encodedPath = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath
        let fullPathString = encodedPath.isEmpty ? baseStr : "\(baseStr)/\(encodedPath)"

        var components = URLComponents(string: fullPathString)
        if let queryItems = queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url ?? URL(string: fullPathString) ?? baseURL
    }

    /// Builds a pre-configured `URLRequest` ready for dispatch.
    public func request(
        baseURL: URL = defaultBaseURL,
        passcodeToken: String? = nil,
        timeoutInterval: TimeInterval = 30.0
    ) -> URLRequest {
        let requestURL = url(baseURL: baseURL)
        var req = URLRequest(url: requestURL, timeoutInterval: timeoutInterval)
        req.httpMethod = httpMethod

        // Standard Mobile Safari User-Agent to pass Cloudflare / DDoS-Guard transparently
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        if let token = passcodeToken, !token.isEmpty {
            req.setValue("passcode_auth=\(token)", forHTTPHeaderField: "Cookie")
        }

        return req
    }
}
