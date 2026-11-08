//
//  DomainConfigurationTests.swift
//  MakabaTests
//
//  Automated unit test suite validating multi-mirror configuration, dynamic base URL routing,
//  failover cycling across verified mirrors (2ch.org, 2ch.hk), custom mirror management,
//  passcode persistence, and URL rewriting.
//

import XCTest
@testable import Makaba

final class DomainConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to default domain and clear custom mirrors before each test
        DomainConfigurationService.shared.setDomain(DomainConfigurationService.defaultDomain)
        for custom in DomainConfigurationService.shared.customMirrors {
            DomainConfigurationService.shared.removeCustomMirror(custom)
        }
        DomainConfigurationService.shared.setPasscode(nil)
    }

    override func tearDown() {
        DomainConfigurationService.shared.setDomain(DomainConfigurationService.defaultDomain)
        for custom in DomainConfigurationService.shared.customMirrors {
            DomainConfigurationService.shared.removeCustomMirror(custom)
        }
        DomainConfigurationService.shared.setPasscode(nil)
        super.tearDown()
    }

    // MARK: - 1. Mirror Registry & Defaults

    func test_availableMirrors_containsVerifiedAndFallbackDomains() {
        let mirrors = DomainConfigurationService.availableMirrors
        XCTAssertTrue(mirrors.contains("https://2ch.hk"), "Must contain verified 2ch.hk")
        XCTAssertTrue(mirrors.contains("https://2ch.org"), "Must contain verified 2ch.org")
        XCTAssertTrue(mirrors.contains("https://2ch.pm"), "Must contain fallback mirror 2ch.pm")
        XCTAssertTrue(mirrors.contains("https://2ch.life"), "Must contain fallback mirror 2ch.life")
        XCTAssertFalse(mirrors.contains("https://2ch.re"), "Dead domain 2ch.re (NXDOMAIN) must be purged")
        XCTAssertEqual(mirrors.count, 4)
    }

    func test_defaultDomain_is2chOrg() {
        XCTAssertEqual(DomainConfigurationService.defaultDomain, "https://2ch.org")
    }

    func test_verifiedMirrors_containsOnlyHealthyJSONDomains() {
        let verified = DomainConfigurationService.verifiedMirrors
        XCTAssertEqual(verified, ["https://2ch.org", "https://2ch.hk"])
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
        service.setDomain("custom-mirror.net")
        XCTAssertEqual(service.currentDomain, "https://custom-mirror.net")
        XCTAssertEqual(service.activeHost, "custom-mirror.net")
    }

    // MARK: - 3. Failover Cycling

    func test_failoverToNextMirror_cyclesThroughVerifiedMirrorsAndWrapsAround() {
        let service = DomainConfigurationService.shared
        let pool = service.autoFailoverMirrors

        service.setDomain(pool[0]) // https://2ch.org
        XCTAssertEqual(service.currentDomain, pool[0])

        let next1 = service.failoverToNextMirror()
        XCTAssertEqual(next1, pool[1]) // https://2ch.hk
        XCTAssertEqual(service.currentDomain, pool[1])

        // Wraps back to first verified mirror
        let wrapped = service.failoverToNextMirror()
        XCTAssertEqual(wrapped, pool[0])
        XCTAssertEqual(service.currentDomain, pool[0])
    }

    // MARK: - 4. Custom Mirror Management

    func test_customMirror_addAndRemove() {
        let service = DomainConfigurationService.shared
        let testMirror = "https://custom-proxy.io"

        let addResult = service.addCustomMirror(testMirror)
        XCTAssertTrue(addResult.success)
        XCTAssertTrue(service.customMirrors.contains(testMirror))
        XCTAssertTrue(service.allMirrors.contains(testMirror))
        XCTAssertTrue(service.autoFailoverMirrors.contains(testMirror))

        service.removeCustomMirror(testMirror)
        XCTAssertFalse(service.customMirrors.contains(testMirror))
        XCTAssertFalse(service.autoFailoverMirrors.contains(testMirror))
    }

    // MARK: - 5. Passcode Persistence

    func test_passcode_saveAndClear() {
        let service = DomainConfigurationService.shared
        let token = "usercode_secret_abc123"

        service.setPasscode(token)
        XCTAssertEqual(service.passcodeToken, token)
        XCTAssertEqual(MakabaAPIClient.shared.passcodeToken, token)

        service.setPasscode(nil)
        XCTAssertNil(service.passcodeToken)
    }

    // MARK: - 6. URL Resolution & Rewriting

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

    // MARK: - 7. Dynamic Integration with Endpoints and API Client

    func test_endpoints_dynamicallyFollowsActiveDomain() {
        let service = DomainConfigurationService.shared

        service.setDomain("https://2ch.org")
        let urlOrg = MakabaEndpoint.boards.url()
        XCTAssertTrue(urlOrg.absoluteString.hasPrefix("https://2ch.org"))

        service.setDomain("https://2ch.hk")
        let urlHk = MakabaEndpoint.boards.url()
        XCTAssertTrue(urlHk.absoluteString.hasPrefix("https://2ch.hk"))

        service.setDomain("https://2ch.pm")
        let urlPm = MakabaEndpoint.catalog(board: "b").url()
        XCTAssertTrue(urlPm.absoluteString.hasPrefix("https://2ch.pm"))
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
