//
//  MultipartFormData.swift
//  Makaba
//
//  RFC 7578 compliant multipart/form-data serializer for binary media and form uploads.
//

import Foundation

/// Builds RFC 7578 compliant `multipart/form-data` payloads for file uploads and form posting.
///
/// Designed as a value type (`struct`) conforming to `Sendable`, guaranteeing thread safety
/// without data races or reference locks.
public struct MultipartFormData: Sendable {
    public let boundary: String
    private let crlf = "\r\n"

    private struct Part: Sendable {
        let headers: [String: String]
        let body: Data
    }

    private var parts: [Part] = []

    public init(boundary: String? = nil) {
        if let customBoundary = boundary, !customBoundary.isEmpty {
            self.boundary = customBoundary
        } else {
            self.boundary = "Boundary-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }
    }

    /// Content-Type header value including the generated boundary token.
    public var contentType: String {
        return "multipart/form-data; boundary=\(boundary)"
    }

    /// Appends a simple UTF-8 text form field.
    public mutating func appendField(name: String, value: String) {
        let headers = [
            "Content-Disposition": "form-data; name=\"\(name)\""
        ]
        let bodyData = Data(value.utf8)
        parts.append(Part(headers: headers, body: bodyData))
    }

    /// Appends an optional text field if value is non-nil and not empty.
    public mutating func appendFieldIfPresent(name: String, value: String?) {
        guard let val = value, !val.isEmpty else { return }
        appendField(name: name, value: val)
    }

    /// Appends a binary file attachment part.
    public mutating func appendFile(name: String = "file[]", filename: String, mimeType: String, data: Data) {
        let headers = [
            "Content-Disposition": "form-data; name=\"\(name)\"; filename=\"\(filename)\"",
            "Content-Type": mimeType
        ]
        parts.append(Part(headers: headers, body: data))
    }

    /// Serializes all added parts into RFC 7578 compliant multipart `Data`.
    public func build() -> Data {
        var result = Data()

        for part in parts {
            result.append(Data("--\(boundary)\(crlf)".utf8))
            for (headerKey, headerVal) in part.headers {
                result.append(Data("\(headerKey): \(headerVal)\(crlf)".utf8))
            }
            result.append(Data(crlf.utf8))
            result.append(part.body)
            result.append(Data(crlf.utf8))
        }

        // Closing delimiter
        result.append(Data("--\(boundary)--\(crlf)".utf8))
        return result
    }

    /// Returns estimated byte size of the serialized payload.
    public var totalSize: Int {
        return build().count
    }
}
