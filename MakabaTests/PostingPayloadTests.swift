//
//  PostingPayloadTests.swift
//  MakabaTests
//
//  Automated unit test suite validating RFC 7578 multipart/form-data serialization,
//  boundary framing, CRLF delimiter integrity, field assembly, and binary media attachment encoding.
//

import XCTest
@testable import Makaba

final class PostingPayloadTests: XCTestCase {

    // MARK: - 1. RFC 7578 Multipart Framing & Delimiters

    func test_multipart_customBoundary_andContentTypeHeader() {
        let customBoundary = "CustomBoundaryTest12345"
        let multipart = MultipartFormData(boundary: customBoundary)

        XCTAssertEqual(multipart.boundary, customBoundary)
        XCTAssertEqual(multipart.contentType, "multipart/form-data; boundary=CustomBoundaryTest12345")
    }

    func test_multipart_defaultBoundary_generatesValidPrefix() {
        let multipart = MultipartFormData()

        XCTAssertTrue(multipart.boundary.hasPrefix("Boundary-"))
        XCTAssertGreaterThan(multipart.boundary.count, 10)
        XCTAssertEqual(multipart.contentType, "multipart/form-data; boundary=\(multipart.boundary)")
    }

    func test_multipart_emptyPayload_containsOnlyClosingBoundary() {
        let boundary = "EmptyTestBoundary"
        let multipart = MultipartFormData(boundary: boundary)
        let data = multipart.build()
        let stringContent = String(data: data, encoding: .utf8)

        // RFC 7578: Empty multipart contains closing delimiter followed by CRLF: --boundary--\r\n
        let expected = "--\(boundary)--\r\n"
        XCTAssertEqual(stringContent, expected)
        XCTAssertEqual(multipart.totalSize, data.count)
    }

    func test_multipart_singleField_strictlyAdheresToCRLFSpec() {
        let boundary = "FieldTestBoundary"
        var multipart = MultipartFormData(boundary: boundary)
        multipart.appendField(name: "task", value: "post")

        let data = multipart.build()
        let stringContent = String(data: data, encoding: .utf8)

        let expected = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"task\"\r\n" +
            "\r\n" +
            "post\r\n" +
            "--\(boundary)--\r\n"

        XCTAssertEqual(stringContent, expected)
        XCTAssertEqual(multipart.totalSize, data.count)
    }

    // MARK: - 2. Field Assembly for Makaba Posting Specification

    func test_multipart_completeFormAssembly_serializesAllPostingParameters() {
        let boundary = "MakabaPostBoundary"
        var multipart = MultipartFormData(boundary: boundary)

        // Core fields matching /user/posting?nc=1 requirements
        multipart.appendField(name: "task", value: "post")
        multipart.appendField(name: "board", value: "b")
        multipart.appendField(name: "thread", value: "338026248")
        multipart.appendField(name: "comment", value: "Привет Двач! Тест постинга.")
        multipart.appendField(name: "captcha_type", value: "emoji_captcha")
        multipart.appendField(name: "emoji_captcha_id", value: "verified_jwe_token_xyz")
        multipart.appendField(name: "2ch_challenge", value: "18847")
        multipart.appendField(name: "email", value: "sage")
        multipart.appendField(name: "subject", value: "Тема треда")
        multipart.appendField(name: "name", value: "Аноним")
        multipart.appendField(name: "sage", value: "1")
        multipart.appendField(name: "op_mark", value: "1")
        multipart.appendField(name: "tags", value: "b,test")
        multipart.appendField(name: "icon", value: "3")

        let data = multipart.build()
        guard let payloadString = String(data: data, encoding: .utf8) else {
            XCTFail("Payload must be valid UTF-8 string")
            return
        }

        // Validate boundary encapsulation
        XCTAssertTrue(payloadString.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(payloadString.hasSuffix("--\(boundary)--\r\n"))

        // Validate all parameter occurrences
        XCTAssertTrue(payloadString.contains("name=\"task\"\r\n\r\npost\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"board\"\r\n\r\nb\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"thread\"\r\n\r\n338026248\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"comment\"\r\n\r\nПривет Двач! Тест постинга.\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"captcha_type\"\r\n\r\nemoji_captcha\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"emoji_captcha_id\"\r\n\r\nverified_jwe_token_xyz\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"2ch_challenge\"\r\n\r\n18847\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"email\"\r\n\r\nsage\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"subject\"\r\n\r\nТема треда\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"name\"\r\n\r\nАноним\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"sage\"\r\n\r\n1\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"op_mark\"\r\n\r\n1\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"tags\"\r\n\r\nb,test\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"icon\"\r\n\r\n3\r\n"))
    }

    func test_multipart_appendFieldIfPresent_skipsNilAndEmpty() {
        let boundary = "PresentCheckBoundary"
        var multipart = MultipartFormData(boundary: boundary)

        multipart.appendField(name: "required_field", value: "value1")
        multipart.appendFieldIfPresent(name: "nil_field", value: nil)
        multipart.appendFieldIfPresent(name: "empty_field", value: "")
        multipart.appendFieldIfPresent(name: "valid_optional", value: "value2")

        let payloadString = String(data: multipart.build(), encoding: .utf8)!

        XCTAssertTrue(payloadString.contains("name=\"required_field\"\r\n\r\nvalue1\r\n"))
        XCTAssertTrue(payloadString.contains("name=\"valid_optional\"\r\n\r\nvalue2\r\n"))
        XCTAssertFalse(payloadString.contains("nil_field"))
        XCTAssertFalse(payloadString.contains("empty_field"))
    }

    // MARK: - 3. Binary File Attachment Encoding

    func test_multipart_binaryFileAttachment_encodesJPEG() {
        let boundary = "FileBoundaryJPEG"
        var multipart = MultipartFormData(boundary: boundary)

        // Raw JPEG magic header: FF D8 FF E0
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]
        let jpegData = Data(jpegBytes)

        multipart.appendFile(
            name: "file[]",
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            data: jpegData
        )

        let builtData = multipart.build()

        // Verify header prefix in payload
        let expectedHeader = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file[]\"; filename=\"photo.jpg\"\r\n" +
            "Content-Type: image/jpeg\r\n" +
            "\r\n"
        let headerData = Data(expectedHeader.utf8)
        let trailingData = Data("\r\n--\(boundary)--\r\n".utf8)

        XCTAssertEqual(builtData.prefix(headerData.count), headerData)
        XCTAssertEqual(builtData.suffix(trailingData.count), trailingData)

        // Extract body slice and verify raw bytes match exactly
        let bodySlice = builtData[headerData.count..<(builtData.count - trailingData.count)]
        XCTAssertEqual(Data(bodySlice), jpegData)
    }

    func test_multipart_binaryFileAttachment_encodesWebMVideo() {
        let boundary = "FileBoundaryWebM"
        var multipart = MultipartFormData(boundary: boundary)

        // EBML header bytes: 1A 45 DF A3
        let webmBytes: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01]
        let webmData = Data(webmBytes)

        multipart.appendFile(
            name: "file[]",
            filename: "clip.webm",
            mimeType: "video/webm",
            data: webmData
        )

        let builtData = multipart.build()
        let expectedHeader = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file[]\"; filename=\"clip.webm\"\r\n" +
            "Content-Type: video/webm\r\n" +
            "\r\n"

        let headerData = Data(expectedHeader.utf8)
        XCTAssertEqual(builtData.prefix(headerData.count), headerData)
    }

    func test_multipart_multipleFiles_areSerializedInOrder() {
        let boundary = "MultiFileBoundary"
        var multipart = MultipartFormData(boundary: boundary)

        let file1 = Data("FILE_ONE_CONTENT".utf8)
        let file2 = Data("FILE_TWO_CONTENT".utf8)

        multipart.appendFile(name: "file[]", filename: "img1.png", mimeType: "image/png", data: file1)
        multipart.appendFile(name: "file[]", filename: "img2.png", mimeType: "image/png", data: file2)

        let builtData = multipart.build()
        let payloadString = String(decoding: builtData, as: UTF8.self)

        XCTAssertTrue(payloadString.contains("filename=\"img1.png\""))
        XCTAssertTrue(payloadString.contains("filename=\"img2.png\""))
        XCTAssertTrue(payloadString.contains("FILE_ONE_CONTENT"))
        XCTAssertTrue(payloadString.contains("FILE_TWO_CONTENT"))

        // img1 must appear before img2
        guard let range1 = payloadString.range(of: "img1.png"),
              let range2 = payloadString.range(of: "img2.png") else {
            XCTFail("Files must be present in payload")
            return
        }
        XCTAssertLessThan(range1.lowerBound, range2.lowerBound)
    }

    // MARK: - 4. PostPayload Model Tests

    func test_postPayload_newThreadVsReply() {
        let newThreadPayload = PostPayload(board: "b", thread: 0, comment: "Новый тред")
        XCTAssertTrue(newThreadPayload.isNewThread)
        XCTAssertEqual(newThreadPayload.task, "post")
        XCTAssertEqual(newThreadPayload.board, "b")

        let replyPayload = PostPayload(board: "b", thread: 338026248, comment: "Ответ")
        XCTAssertFalse(replyPayload.isNewThread)
        XCTAssertEqual(replyPayload.thread, 338026248)
    }

    func test_postFileAttachment_structProperties() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let attachment = PostFileAttachment(fileName: "test.png", mimeType: "image/png", data: data)

        XCTAssertEqual(attachment.fileName, "test.png")
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertEqual(attachment.data, data)
    }
}
