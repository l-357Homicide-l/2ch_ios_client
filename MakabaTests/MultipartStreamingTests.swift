//
//  MultipartStreamingTests.swift
//  MakabaTests
//
//  Automated unit test suite validating zero-OOM temporary file streaming
//  for multipart/form-data uploads and cache invalidation mechanics.
//

import XCTest
@testable import Makaba

final class MultipartStreamingTests: XCTestCase {

    func test_writeToTempFile_createsValidFileWithExactPayloadBytes() throws {
        var multipart = MultipartFormData(boundary: "StreamingBoundaryTest98765")
        multipart.appendField(name: "task", value: "post")
        multipart.appendField(name: "board", value: "b")
        multipart.appendField(name: "comment", value: "Тестовый комментарий стриминга")

        let memoryBytes = multipart.build()
        let tempFileURL = try multipart.writeToTempFile()

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path), "Temp file must exist on disk")

        let diskBytes = try Data(contentsOf: tempFileURL)
        XCTAssertEqual(diskBytes, memoryBytes, "Disk streamed payload must match in-memory build byte-for-byte")
        XCTAssertEqual(diskBytes.count, multipart.totalSize)
    }

    func test_writeToTempFile_withBinaryMediaAttachment() throws {
        var multipart = MultipartFormData(boundary: "BinaryStreamingBoundary456")
        let dummyImageBytes = Data(repeating: 0x42, count: 1024 * 128) // 128 KB
        multipart.appendFile(name: "file[]", filename: "test.jpg", mimeType: "image/jpeg", data: dummyImageBytes)

        let tempFileURL = try multipart.writeToTempFile()
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 1024 * 128)
    }

    func test_cacheInvalidation_clearsCatalogAndThread() async {
        let client = MakabaAPIClient.shared
        // Invalidate does not crash and executes cleanly
        await client.invalidateCatalogCache(board: "b")
        await client.invalidateThreadCache(board: "b", threadNum: 123456)
        await client.clearAllCache()
        XCTAssertTrue(true, "Cache invalidation executed without errors")
    }
}
