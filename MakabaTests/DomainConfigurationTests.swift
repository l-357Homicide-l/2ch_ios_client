//
//  DomainConfigurationTests.swift
//  MakabaTests
//
//  Automated unit test suite validating multi-mirror configuration, dynamic base URL routing,
//  failover cycling across 2ch.hk / 2ch.org / 2ch.pm / 2ch.re / 2ch.life, and URL rewriting.
//

import XCTest
@testable import Makaba

final class DomainConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to default domain before each test
        DomainConfigurationService.shared.setDomain(DomainConfigurationService.defaultDomain)
    }

    override func tearDown() {
        DomainConfigurationService.shared.setDomain(DomainConfigurationService.defaultDomain)
        super.tearDown()
    }

    // MARK: - 1. Mirror Registry & Defaults

    func test_availableMirrors_containsAllRequiredDomains() {
        let mirrors = DomainConfigurationService.availableMirrors
        XCTAssertTrue(mirrors.contains("https://2ch.hk"), "Must contain primary 2ch.hk")
        XCTAssertTrue(mirrors.contains("https://2ch.org"), "Must contain mirror 2ch.org")
        XCTAssertTrue(mirrors.contains("https://2ch.pm"), "Must contain backup mirror 2ch.pm")
        XCTAssertTrue(mirrors.contains("https://2ch.re"), "Must contain backup mirror 2ch.re")
        XCTAssertTrue(mirrors.contains("https://2ch.life"), "Must contain community mirror 2ch.life")
        XCTAssertEqual(mirrors.count, 5)
    }

    func test_defaultDomain_is2chOrg() {
        XCTAssertEqual(DomainConfigurationService.defaultDomain, "https://2ch.org")
    }

    // MARK: - 2. Domain Switching & Host Resolution

    func test_setDomain_updatesActiveDomainAndHost() {
        let service = DomainConfigurationService.shared

        service.setDomain("https://2ch.hk")
        XCTAssertEqual(service.currentDomain, "https://2ch.hk")
        XCTAssertEqual(service.baseURL.absoluteString, "https://2ch.hk")
        XCTAssertEqual(service.activeHost, "2ch.hk")

        service.setDomain("https://2ch.pm")
        XCTAssertEqual(service.currentDomain, "https://2ch.pm")
        XCTAssertEqual(service.baseURL.absoluteString, "https://2ch.pm")
        XCTAssertEqual(service.activeHost, "2ch.pm")
    }

    func test_setDomain_normalizesScheme() {
        let service = DomainConfigurationService.shared
        service.setDomain("2ch.re")
        XCTAssertEqual(service.currentDomain, "https://2ch.re")
        XCTAssertEqual(service.activeHost, "2ch.re")
    }

    // MARK: - 3. Failover Cycling

    func test_failoverToNextMirror_cyclesThroughAllMirrorsAndWrapsAround() {
        let service = DomainConfigurationService.shared
        let mirrors = DomainConfigurationService.availableMirrors

        service.setDomain(mirrors[0]) // https://2ch.org
        XCTAssertEqual(service.currentDomain, mirrors[0])

        let next1 = service.failoverToNextMirror()
        XCTAssertEqual(next1, mirrors[1]) // https://2ch.hk
        XCTAssertEqual(service.currentDomain, mirrors[1])

        let next2 = service.failoverToNextMirror()
        XCTAssertEqual(next2, mirrors[2]) // https://2ch.pm

        let next3 = service.failoverToNextMirror()
        XCTAssertEqual(next3, mirrors[3]) // https://2ch.re

        let next4 = service.failoverToNextMirror()
        XCTAssertEqual(next4, mirrors[4]) // https://2ch.life

        // Wraps back to first mirror
        let wrapped = service.failoverToNextMirror()
        XCTAssertEqual(wrapped, mirrors[0])
        XCTAssertEqual(service.currentDomain, mirrors[0])
    }

    // MARK: - 4. URL Resolution & Rewriting

    func test_buildURL_resolvesRelativePathsCorrectly() {
        let service = DomainConfigurationService.shared
        service.setDomain("https://2ch.hk")

        let url1 = service.buildURL(path: "/b/res/12345.html")
        XCTAssertEqual(url1?.absoluteString, "https://2ch.hk/b/res/12345.html")

        let url2 = service.buildURL(path: "api/mobile/v2/boards")
        XCTAssertEqual(url2?.absoluteString, "https://2ch.hk/api/mobile/v2/boards")
    }

    func test_buildURL_preservesAbsoluteExternalURLs() {
        let service = DomainConfigurationService.shared
        service.setDomain("https://2ch.hk")

        let external = "https://cdn.example.com/image.png"
        let resolved = service.buildURL(path: external)
        XCTAssertEqual(resolved?.absoluteString, external)
    }

    func test_rewriteURL_switchesHostPreservingPathAndQuery() {
        let service = DomainConfigurationService.shared
        let original = URL(string: "https://2ch.org/api/captcha/settings?board=b&thread=100")!

        let rewritten = service.rewriteURL(original, to: "https://2ch.pm")
        XCTAssertEqual(rewritten?.scheme, "https")
        XCTAssertEqual(rewritten?.host, "2ch.pm")
        XCTAssertEqual(rewritten?.path, "/api/captcha/settings")
        XCTAssertEqual(rewritten?.query, "board=b&thread=100")
    }

    // MARK: - 5. Dynamic Integration with Endpoints and API Client

    func test_endpoints_dynamicallyFollowsActiveDomain() {
        let service = DomainConfigurationService.shared

        service.setDomain("https://2ch.org")
        let urlOrg = MakabaEndpoint.boards.url()
        XCTAssertTrue(urlOrg.absoluteString.hasPrefix("https://2ch.org"))

        service.setDomain("https://2ch.hk")
        let urlHk = MakabaEndpoint.boards.url()
        XCTAssertTrue(urlHk.absoluteString.hasPrefix("https://2ch.hk"))

        service.setDomain("https://2ch.re")
        let urlRe = MakabaEndpoint.catalog(board: "b").url()
        XCTAssertTrue(urlRe.absoluteString.hasPrefix("https://2ch.re"))
    }

    func test_apiClient_dynamicallyFollowsActiveDomain() {
        let service = DomainConfigurationService.shared
        let client = MakabaAPIClient.shared

        service.setDomain("https://2ch.org")
        XCTAssertEqual(client.baseURL.host, "2ch.org")

        service.setDomain("https://2ch.hk")
        XCTAssertEqual(client.baseURL.host, "2ch.hk")
    }
}
