import XCTest
@testable import AdGuardControl

final class URLNormalizerTests: XCTestCase {
    func testKeepsFullHTTPAddressWithPort() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("http://100.64.0.5:3000"), "http://100.64.0.5:3000")
    }

    func testAddsHTTPWhenSchemeMissing() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("adguard-home:3000"), "http://adguard-home:3000")
        XCTAssertEqual(try URLNormalizer.normalizedString("192.168.1.10:3000"), "http://192.168.1.10:3000")
    }

    func testMagicDNSHostIsLowercased() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("HTTP://AdGuard-Home.Tailnet-Name.TS.net:3000"),
                       "http://adguard-home.tailnet-name.ts.net:3000")
    }

    func testStripsTrailingSlashAndControlSuffix() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("http://host:3000/"), "http://host:3000")
        XCTAssertEqual(try URLNormalizer.normalizedString("http://host:3000/control"), "http://host:3000")
        XCTAssertEqual(try URLNormalizer.normalizedString("http://host:3000/control/"), "http://host:3000")
        XCTAssertEqual(try URLNormalizer.normalizedString("http://host:3000/adguard/control"), "http://host:3000/adguard")
    }

    func testSupportsHTTPS() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("https://dns.example.org:443"), "https://dns.example.org:443")
    }

    func testTrimsWhitespaceAndDropsCredentialsQueryFragment() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("  http://user:pw@host:3000?x=1#frag \n"), "http://host:3000")
    }

    func testRejectsInvalidInput() {
        for input in ["", "   ", "ftp://host:3000", "http://", "http://host:99999", "http://ho st:3000"] {
            XCTAssertThrowsError(try URLNormalizer.normalize(input), input) { error in
                XCTAssertEqual(error as? APIError, .invalidURL)
            }
        }
    }

    func testTailscaleHostDetection() {
        XCTAssertTrue(TailscaleHelper.isTailscaleIPv4("100.64.0.1"))
        XCTAssertTrue(TailscaleHelper.isTailscaleIPv4("100.127.255.254"))
        XCTAssertFalse(TailscaleHelper.isTailscaleIPv4("100.128.0.1"))
        XCTAssertFalse(TailscaleHelper.isTailscaleIPv4("100.63.0.1"))
        XCTAssertFalse(TailscaleHelper.isTailscaleIPv4("192.168.1.10"))
        XCTAssertTrue(TailscaleHelper.looksLikeTailnetHost("adguard-home.tailnet-name.ts.net"))
        XCTAssertTrue(TailscaleHelper.looksLikeTailnetHost("adguard-home"))
        XCTAssertTrue(TailscaleHelper.looksLikeTailnetHost("100.100.1.1"))
        XCTAssertFalse(TailscaleHelper.looksLikeTailnetHost("192.168.1.10"))
        XCTAssertFalse(TailscaleHelper.looksLikeTailnetHost("dns.example.org"))
    }
}
