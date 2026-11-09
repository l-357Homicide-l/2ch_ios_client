//
//  KeychainServiceTests.swift
//  MakabaTests
//
//  Unit tests validating secure storage, retrieval, updating, and deletion
//  of credentials using KeychainService.
//

import XCTest
@testable import Makaba

final class KeychainServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainService.deletePasscode()
    }

    override func tearDown() {
        KeychainService.deletePasscode()
        super.tearDown()
    }

    func test_saveAndLoadPasscode() {
        let testToken = "test_vip_passcode_12345"
        let saved = KeychainService.savePasscode(testToken)
        XCTAssertTrue(saved, "Saving passcode to Keychain must succeed")

        let loaded = KeychainService.loadPasscode()
        XCTAssertEqual(loaded, testToken, "Loaded passcode must match saved passcode")
    }

    func test_overwritePasscode() {
        let initialToken = "first_token"
        let updatedToken = "second_token_updated"

        XCTAssertTrue(KeychainService.savePasscode(initialToken))
        XCTAssertEqual(KeychainService.loadPasscode(), initialToken)

        XCTAssertTrue(KeychainService.savePasscode(updatedToken))
        XCTAssertEqual(KeychainService.loadPasscode(), updatedToken, "Overwritten passcode must return new token")
    }

    func test_deletePasscode() {
        let token = "token_to_delete"
        XCTAssertTrue(KeychainService.savePasscode(token))
        XCTAssertEqual(KeychainService.loadPasscode(), token)

        let deleted = KeychainService.deletePasscode()
        XCTAssertTrue(deleted, "Deleting passcode must succeed")

        let loadedAfterDelete = KeychainService.loadPasscode()
        XCTAssertNil(loadedAfterDelete, "Loading deleted passcode must return nil")
    }

    func test_deletePasscode_whenNonExistent_succeeds() {
        // Should not throw or fail when deleting non-existent entry
        let deleted = KeychainService.deletePasscode()
        XCTAssertTrue(deleted, "Deleting nonexistent passcode should return success")
    }
}
