//
//  PoWSolverTests.swift
//  MakabaTests
//
//  Automated unit test suite validating SHA-512 Proof of Work nonce discovery,
//  production test vectors, boundary limits, normalization, and async cooperative cancellation.
//

import XCTest
import CryptoKit
@testable import Makaba

final class PoWSolverTests: XCTestCase {

    // MARK: - 1. Production Test Vectors

    /// Production Test Vector 1 (from POW_CAPTCHA_SPEC.md §3.3)
    func test_solve_productionVector1_resolvesNonce18847() throws {
        let template = "7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv"
        let targetHash = "4014d34ffe01240df12aede0650bf7f1c35fdd2be915b8cd44f06922411095a30f764053ddee008be1e2b54750ba36997acfba96d0453d114043eb615cc5be98"
        let limit = 20000

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: limit)

        XCTAssertEqual(result.nonce, 18847)
        XCTAssertEqual(result.hash, targetHash.lowercased())
        XCTAssertGreaterThan(result.durationMs, 0.0)
    }

    /// Production Test Vector 2 (from POW_CAPTCHA_SPEC.md §3.3)
    func test_solve_productionVector2_resolvesNonce8214() throws {
        let template = "qWIxksPn9V2oRLk5%d6grw3pvMHinm3uFf"
        let targetHash = "b73c8af810b9cfcd266cae6d2c140308b3d23c0addd807386cf161d06c535ee07b6f0f1368bac9b991817e8e7bc004b560fcaad75be269959c41540ee291a7eb"
        let limit = 20000

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: limit)

        XCTAssertEqual(result.nonce, 8214)
        XCTAssertEqual(result.hash, targetHash.lowercased())
        XCTAssertGreaterThan(result.durationMs, 0.0)
    }

    /// Production Test Vector 3 (from POW_CAPTCHA_SPEC.md §3.3)
    func test_solve_productionVector3_resolvesNonce17949() throws {
        let template = "bFZchwAOHvAealh9%dq11tvQUk5MFSFxaD"
        let targetHash = "ed241cab9a1eff97e47e8d18f22f380bf02c58b39b5f7cc3e858de28b2556edc8e11304d0bfe7c900cac9cc112324a58e69e2226c22dc7ff1cedd5ecfb91945e"
        let limit = 20000

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: limit)

        XCTAssertEqual(result.nonce, 17949)
        XCTAssertEqual(result.hash, targetHash.lowercased())
        XCTAssertGreaterThan(result.durationMs, 0.0)
    }

    /// Production Test Vector with suffixless template format (`...%d`)
    func test_solve_suffixlessTemplate_resolvesNonce18847() throws {
        let template = "a98a0d4c6534571d187210e74f11481b7a2d486f0c6c9656dcbe1515b22b6473%d"
        // SHA-512 of template with 18847
        let candidate = "a98a0d4c6534571d187210e74f11481b7a2d486f0c6c9656dcbe1515b22b647318847"
        let digest = SHA512.hash(data: candidate.data(using: .utf8)!)
        let targetHash = digest.map { String(format: "%02x", $0) }.joined()

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: 20000)

        XCTAssertEqual(result.nonce, 18847)
        XCTAssertEqual(result.hash, targetHash)
    }

    // MARK: - 2. Boundary Condition Tests

    /// Boundary Test: Nonce at index 0 (first element of interval [0, limit))
    func test_solve_nonceZero_resolvesImmediately() throws {
        let template = "zero_test_%d_end"
        let candidate = "zero_test_0_end"
        let digest = SHA512.hash(data: candidate.data(using: .utf8)!)
        let targetHash = digest.map { String(format: "%02x", $0) }.joined()

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: 100)

        XCTAssertEqual(result.nonce, 0)
        XCTAssertEqual(result.hash, targetHash)
    }

    /// Boundary Test: Nonce at boundary limit - 1 (last element of interval [0, limit))
    func test_solve_nonceAtLimitMinusOne_resolvesSuccessfully() throws {
        let limit = 50
        let targetNonce = limit - 1 // 49
        let template = "boundary_%d_chk"
        let candidate = "boundary_\(targetNonce)_chk"
        let digest = SHA512.hash(data: candidate.data(using: .utf8)!)
        let targetHash = digest.map { String(format: "%02x", $0) }.joined()

        let result = try PoWSolver.solve(template: template, targetHash: targetHash, limit: limit)

        XCTAssertEqual(result.nonce, targetNonce)
        XCTAssertEqual(result.hash, targetHash)
    }

    /// Boundary Test: Nonce exactly equal to limit (nonce >= limit must throw limitExceeded)
    func test_solve_nonceAtOrExceedingLimit_throwsLimitExceeded() {
        let limit = 50
        let targetNonce = 50 // Out of interval [0, 50)
        let template = "exceeded_%d_test"
        let candidate = "exceeded_\(targetNonce)_test"
        let digest = SHA512.hash(data: candidate.data(using: .utf8)!)
        let targetHash = digest.map { String(format: "%02x", $0) }.joined()

        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: targetHash, limit: limit)) { error in
            guard case PoWError.limitExceeded(let thrownLimit) = error else {
                XCTFail("Expected PoWError.limitExceeded, received \(error)")
                return
            }
            XCTAssertEqual(thrownLimit, limit)
        }
    }

    /// Boundary Test: Zero or negative limit must throw limitExceeded immediately
    func test_solve_nonPositiveLimit_throwsLimitExceeded() {
        let template = "prefix_%d"
        let dummyHash = String(repeating: "a", count: 128)

        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: dummyHash, limit: 0)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.limitExceeded(0))
        }

        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: dummyHash, limit: -10)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.limitExceeded(-10))
        }
    }

    // MARK: - 3. Target Hash Normalization & Input Hardening

    /// Verifies uppercase hexadecimal target strings and leading/trailing whitespace are normalized
    func test_solve_uppercaseTargetAndWhitespace_normalizesCorrectly() throws {
        let template = "prefix_%d_suffix"
        let candidate = "prefix_42_suffix"
        let digest = SHA512.hash(data: candidate.data(using: .utf8)!)
        let lowercaseHex = digest.map { String(format: "%02x", $0) }.joined()
        let uppercaseHexWithWhitespace = " \n\t  \(lowercaseHex.uppercased())  \r\n "

        let result = try PoWSolver.solve(template: template, targetHash: uppercaseHexWithWhitespace, limit: 100)

        XCTAssertEqual(result.nonce, 42)
        XCTAssertEqual(result.hash, lowercaseHex)
    }

    /// Verifies invalid template without `%d` throws invalidTemplate
    func test_solve_missingSubstitutionMarker_throwsInvalidTemplate() {
        let template = "missing_marker_entirely"
        let dummyHash = String(repeating: "a", count: 128)

        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: dummyHash, limit: 100)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.invalidTemplate)
        }
    }

    /// Verifies template containing multiple `%d` markers throws invalidTemplate
    func test_solve_multipleSubstitutionMarkers_throwsInvalidTemplate() {
        let template = "prefix_%d_middle_%d_suffix"
        let dummyHash = String(repeating: "a", count: 128)

        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: dummyHash, limit: 100)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.invalidTemplate)
        }
    }

    /// Verifies target hash not matching 128 hexadecimal characters throws invalidTargetHash
    func test_solve_malformedTargetHash_throwsInvalidTargetHash() {
        let template = "prefix_%d"

        // Too short (64 chars instead of 128)
        let tooShortHash = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: tooShortHash, limit: 100)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.invalidTargetHash)
        }

        // 128 chars but non-hexadecimal characters ('z')
        let nonHexHash = String(repeating: "z", count: 128)
        XCTAssertThrowsError(try PoWSolver.solve(template: template, targetHash: nonHexHash, limit: 100)) { error in
            XCTAssertEqual(error as? PoWError, PoWError.invalidTargetHash)
        }
    }

    // MARK: - 4. Asynchronous Solving & Cooperative Task Cancellation

    /// Validates asynchronous solveAsync method resolves target correctly
    func test_solveAsync_resolvesProductionNonce() async throws {
        let template = "7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv"
        let targetHash = "4014d34ffe01240df12aede0650bf7f1c35fdd2be915b8cd44f06922411095a30f764053ddee008be1e2b54750ba36997acfba96d0453d114043eb615cc5be98"

        let result = try await PoWSolver.solveAsync(template: template, targetHash: targetHash, limit: 20000)

        XCTAssertEqual(result.nonce, 18847)
        XCTAssertEqual(result.hash, targetHash)
    }

    /// Validates cooperative task cancellation halts computation without hanging
    func test_solveAsync_whenTaskCancelled_throwsCancellationError() async {
        let template = "unsolvable_%d_token"
        // Target hash that does not exist in [0, 100000)
        let unreachableHash = String(repeating: "f", count: 128)

        let task = Task {
            try await PoWSolver.solveAsync(template: template, targetHash: unreachableHash, limit: 100000)
        }

        // Cancel immediately
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation error to be thrown")
        } catch {
            // Task cancellation manifests as CancellationError or PoWError.cancelled
            XCTAssertTrue(error is CancellationError || (error as? PoWError) == .cancelled || Task.isCancelled)
        }
    }
}
