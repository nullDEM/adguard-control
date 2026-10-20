import XCTest
@testable import AdGuardControl

final class AddressPolicyTests: XCTestCase {
    func testClassifiesIPv4Ranges() {
        XCTAssertEqual(AddressPolicy.classify(host: "100.101.102.103"), .tailnet)
        XCTAssertEqual(AddressPolicy.classify(host: "100.64.0.1"), .tailnet)
        XCTAssertEqual(AddressPolicy.classify(host: "100.128.0.1"), .publicInternet)
        XCTAssertEqual(AddressPolicy.classify(host: "192.168.1.10"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "10.0.0.15"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "172.20.1.1"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "172.32.0.1"), .publicInternet)
        XCTAssertEqual(AddressPolicy.classify(host: "127.0.0.1"), .loopback)
        XCTAssertEqual(AddressPolicy.classify(host: "8.8.8.8"), .publicInternet)
    }

    func testForbidsSpecialAddresses() {
        for host in ["0.0.0.0", "255.255.255.255", "169.254.169.254", "224.0.0.1", "239.255.255.250", "::", "ff02::1"] {
            XCTAssertEqual(AddressPolicy.classify(host: host), .forbidden, host)
        }
    }

    func testClassifiesNames() {
        XCTAssertEqual(AddressPolicy.classify(host: "adguard"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "pi.local"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "pi.home.arpa"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "pi.tail1234.ts.net"), .tailnet)
        XCTAssertEqual(AddressPolicy.classify(host: "localhost"), .loopback)
        XCTAssertEqual(AddressPolicy.classify(host: "dns.example.org"), .publicInternet)
    }

    func testClassifiesIPv6() {
        XCTAssertEqual(AddressPolicy.classify(host: "::1"), .loopback)
        XCTAssertEqual(AddressPolicy.classify(host: "fd7a:115c:a1e0::1"), .tailnet)
        XCTAssertEqual(AddressPolicy.classify(host: "fd00::1"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "fe80::1"), .privateNetwork)
        XCTAssertEqual(AddressPolicy.classify(host: "2001:db8::1"), .publicInternet)
        XCTAssertEqual(AddressPolicy.classify(host: "[fd7a:115c:a1e0::1]"), .tailnet)
    }

    func testBlocksCleartextToPublicHostsButAllowsHTTPS() throws {
        XCTAssertThrowsError(try URLNormalizer.normalize("http://dns.example.org:3000")) {
            XCTAssertEqual($0 as? APIError, .insecureTransport)
        }
        XCTAssertThrowsError(try URLNormalizer.normalize("8.8.8.8")) {
            XCTAssertEqual($0 as? APIError, .insecureTransport)
        }
        XCTAssertNoThrow(try URLNormalizer.normalize("https://dns.example.org"))
        XCTAssertNoThrow(try URLNormalizer.normalize("http://100.101.102.103"))
        XCTAssertNoThrow(try URLNormalizer.normalize("http://pi.local"))
    }

    func testRejectsForbiddenAddresses() {
        for input in ["http://169.254.169.254", "http://0.0.0.0:3000", "https://255.255.255.255", "http://224.0.0.1"] {
            XCTAssertThrowsError(try URLNormalizer.normalize(input), input) {
                XCTAssertEqual($0 as? APIError, .forbiddenAddress, input)
            }
        }
    }

    func testNormalizesIPv6WithPort() throws {
        let url = try URLNormalizer.normalize("http://[fd7a:115c:a1e0::1]:3000/")
        XCTAssertEqual(url.port, 3000)
        XCTAssertEqual(url.host, "fd7a:115c:a1e0::1")
        XCTAssertEqual(url.scheme, "http")
    }

    func testPortlessAddressMeansPort80() throws {
        XCTAssertEqual(try URLNormalizer.normalizedString("http://100.101.102.103"), "http://100.101.102.103")
    }
}

final class ProfileValidatorTests: XCTestCase {
    func testUsernameWithColonIsRejected() {
        XCTAssertNotNil(ProfileValidator.usernameError("ad:min"))
        XCTAssertNotNil(ProfileValidator.usernameError("ad\u{0007}min"))
        XCTAssertNil(ProfileValidator.usernameError("admin"))
        XCTAssertNil(ProfileValidator.usernameError("zażółć"))
    }

    func testNameAndAddressMessages() {
        XCTAssertNotNil(ProfileValidator.nameError("   "))
        XCTAssertNil(ProfileValidator.nameError("Raspberry Pi"))
        XCTAssertNil(ProfileValidator.addressError(""), "puste pole nie jest jeszcze błędem")
        XCTAssertNotNil(ProfileValidator.addressError("ftp://host"))
        XCTAssertEqual(ProfileValidator.addressError("http://example.org"), APIError.insecureTransport.errorDescription)
        XCTAssertNil(ProfileValidator.addressError("http://100.64.0.1:3000"))
    }

    func testTransportWarningOnlyForLANWithoutTailscale() {
        XCTAssertNotNil(ProfileValidator.transportWarning(address: "http://192.168.1.10", requireTailscale: false))
        XCTAssertNil(ProfileValidator.transportWarning(address: "http://192.168.1.10", requireTailscale: true))
        XCTAssertNil(ProfileValidator.transportWarning(address: "http://100.64.0.1:3000", requireTailscale: false))
        XCTAssertNil(ProfileValidator.transportWarning(address: "https://192.168.1.10", requireTailscale: false))
    }

    @MainActor
    func testAppStateRejectsInvalidProfilesAndAddresses() throws {
        let app = try TestSupport.makeApp()
        let bad = ServerProfile(name: "X", address: "http://100.64.0.9:3000", username: "a:b")
        XCTAssertThrowsError(try app.save(profile: bad, password: "p"))
        let insecure = ServerProfile(name: "X", address: "http://example.org", username: "a")
        XCTAssertThrowsError(try app.save(profile: insecure, password: "p"))
        XCTAssertEqual(app.profiles.count, 1)
    }

    @MainActor
    func testLegacyProfileWithPublicHTTPAddressGetsNoClient() throws {
        let app = try TestSupport.makeApp()
        let legacy = ServerProfile(name: "Old", address: "http://example.org:3000", username: "a")
        XCTAssertNil(app.makeClient(for: legacy, password: "p"), "Poświadczenia nie mogą być wysłane otwartym tekstem")
    }
}

final class TransportSecurityTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    func testRedirectDelegateRefusesAllRedirects() {
        let delegate = NoRedirectDelegate()
        let original = URL(string: "http://100.64.0.5:3000/control/status")!
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "http://evil.example/steal"])!
        let task = URLSession.shared.dataTask(with: original)
        let called = expectation(description: "completion")
        delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "http://evil.example/steal")!)) { newRequest in
            XCTAssertNil(newRequest, "Delegat musi odmówić przekierowania, żeby nie wysłać Authorization dalej")
            called.fulfill()
        }
        wait(for: [called], timeout: 1)
        task.cancel()
    }

    /// ATS jest wyłączony (nie obejmuje zakresu Tailscale), więc to klient musi odmówić HTTP do hostów publicznych.
    func testClientRefusesCleartextToPublicHostBeforeSendingAnything() async {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: "{}", for: $0) }
        let client = AdGuardAPIClient(baseURL: URL(string: "http://example.org:3000")!, username: "admin", password: "secret",
                                      session: TestSupport.session(), tailscaleProbe: StubTailscale(active: true))
        do {
            _ = try await client.status()
            XCTFail("Oczekiwano błędu")
        } catch {
            XCTAssertEqual(error as? APIError, .insecureTransport)
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty, "Poświadczenia nie mogą opuścić urządzenia otwartym tekstem")
    }

    func testClientAllowsHTTPToTailnetAndPrivateHosts() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v1"}"#, for: $0) }
        for base in ["http://100.101.102.103", "http://192.168.1.10:3000", "http://pi.local", "http://pi.tail1234.ts.net"] {
            let client = AdGuardAPIClient(baseURL: URL(string: base)!, username: "a", password: "b",
                                          session: TestSupport.session(), tailscaleProbe: StubTailscale(active: true))
            _ = try await client.status()
        }
        XCTAssertEqual(MockURLProtocol.requests.count, 4)
    }

    func testRedirectStatusBecomesReadableError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": "https://other.example/"])!
            return (response, Data())
        }
        do {
            _ = try await TestSupport.client().status()
            XCTFail("Oczekiwano błędu")
        } catch let error as APIError {
            guard case .server(let status, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status, 302)
            XCTAssertTrue(message.contains("przekierował"))
        } catch { XCTFail("\(error)") }
    }

    func testHTMLErrorBodyIsSanitized() async {
        MockURLProtocol.handler = { request in
            TestSupport.respond(status: 502, json: "<html><body><h1>Bad   gateway</h1>\n<p>nginx</p></body></html>", for: request)
        }
        do {
            _ = try await TestSupport.client().status()
            XCTFail("Oczekiwano błędu")
        } catch let error as APIError {
            guard case .server(_, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(message, "Bad gateway nginx")
        } catch { XCTFail("\(error)") }
    }

    func testLongErrorBodyIsTruncated() {
        let text = AdGuardAPIClient.sanitize(String(repeating: "a", count: 1000))
        XCTAssertEqual(text.count, 161)
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testJSONErrorMessageIsUsed() {
        XCTAssertEqual(AdGuardAPIClient.message(from: Data(#"{"message":"bad config"}"#.utf8)), "bad config")
    }

    func testBasicAuthWithSpecialCharacters() {
        let header = AdGuardAPIClient.basicAuthHeader(username: "admin", password: "pa:ss żółć")
        let encoded = String(header.dropFirst("Basic ".count))
        XCTAssertEqual(String(data: Data(base64Encoded: encoded)!, encoding: .utf8), "admin:pa:ss żółć")
    }

    func testAuthorizationHeaderNeverAppearsInErrors() async {
        MockURLProtocol.handler = { request in TestSupport.respond(status: 500, json: "oops", for: request) }
        do {
            _ = try await TestSupport.client(password: "TOP-SECRET").status()
            XCTFail()
        } catch {
            let text = "\(error) \((error as? APIError)?.errorDescription ?? "")"
            XCTAssertFalse(text.contains("TOP-SECRET"))
            XCTAssertFalse(text.contains(AdGuardAPIClient.basicAuthHeader(username: "admin", password: "TOP-SECRET")))
        }
    }

    func testTailscaleInterfaceRequiresTunnelName() {
        XCTAssertTrue(TailscaleHelper.isTailscaleInterface(name: "utun3", ipv4: "100.100.1.1"))
        XCTAssertFalse(TailscaleHelper.isTailscaleInterface(name: "pdp_ip0", ipv4: "100.65.2.3"), "CGNAT operatora to nie Tailscale")
        XCTAssertFalse(TailscaleHelper.isTailscaleInterface(name: "en0", ipv4: "100.64.0.9"))
        XCTAssertFalse(TailscaleHelper.isTailscaleInterface(name: "utun3", ipv4: "192.168.1.2"))
    }

    func testErrorTitlesAndSymbols() {
        XCTAssertEqual(APIError.tailscaleRequired.title, "Brak połączenia z Tailscale")
        XCTAssertEqual(APIError.unauthorized.title, "Brak dostępu")
        XCTAssertEqual(APIError.insecureTransport.title, "Nieprawidłowy adres serwera")
        XCTAssertEqual(APIError.timeout.title, "Błąd połączenia")
        XCTAssertFalse(APIError.insecureTransport.diagnostics.isEmpty)
    }
}
