import XCTest
@testable import AdGuardControl

final class APIClientTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    // MARK: Basic Auth i adresy

    func testBasicAuthHeaderIsBase64OfUserAndPassword() {
        // "admin:secret" → YWRtaW46c2VjcmV0
        XCTAssertEqual(AdGuardAPIClient.basicAuthHeader(username: "admin", password: "secret"), "Basic YWRtaW46c2VjcmV0")
        let unicode = AdGuardAPIClient.basicAuthHeader(username: "użytkownik", password: "hasło:z:dwukropkami")
        let token = String(unicode.dropFirst("Basic ".count))
        XCTAssertEqual(String(data: Data(base64Encoded: token)!, encoding: .utf8), "użytkownik:hasło:z:dwukropkami")
    }

    func testRequestsGoToControlPathWithAuthorization() async throws {
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v0.107.50","running":true}"#, for: $0) }
        _ = try await TestSupport.client().status()

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://100.64.0.5:3000/control/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YWRtaW46c2VjcmV0")
    }

    func testBaseURLWithSubpathKeepsPrefix() throws {
        let client = AdGuardAPIClient(baseURL: URL(string: "https://example.org/adguard")!, username: "a", password: "b")
        XCTAssertEqual(try client.makeURL(path: "/querylog", query: [URLQueryItem(name: "limit", value: "5")]).absoluteString,
                       "https://example.org/adguard/control/querylog?limit=5")
    }

    // MARK: Błędy

    func testUnauthorizedMapsTo401Error() async {
        MockURLProtocol.handler = { TestSupport.respond(status: 401, json: "Unauthorized", for: $0) }
        await assertThrows(.unauthorized) { _ = try await TestSupport.client().status() }
    }

    func testForbiddenMapsToForbidden() async {
        MockURLProtocol.handler = { TestSupport.respond(status: 403, for: $0) }
        await assertThrows(.forbidden) { _ = try await TestSupport.client().status() }
    }

    func testServerErrorCarriesMessage() async {
        MockURLProtocol.handler = { TestSupport.respond(status: 500, json: #"{"message":"boom"}"#, for: $0) }
        await assertThrows(.server(status: 500, message: "boom")) { _ = try await TestSupport.client().status() }
    }

    func testPlainTextServerErrorIsTrimmed() async {
        MockURLProtocol.handler = { TestSupport.respond(status: 400, json: "  bad request \n", for: $0) }
        await assertThrows(.server(status: 400, message: "bad request")) { _ = try await TestSupport.client().status() }
    }

    func testNotImplementedMapsTo501() async {
        MockURLProtocol.handler = { TestSupport.respond(status: 501, json: #"{"message":"not supported"}"#, for: $0) }
        await assertThrows(.notImplemented("not supported")) { _ = try await TestSupport.client().dhcpStatus() }
    }

    func testURLErrorsAreMapped() async {
        let cases: [(URLError.Code, APIError)] = [
            (.timedOut, .timeout),
            (.notConnectedToInternet, .noConnection),
            (.cannotConnectToHost, .hostUnreachable),
            (.cannotFindHost, .hostUnreachable),
            (.cancelled, .cancelled)
        ]
        for (code, expected) in cases {
            MockURLProtocol.handler = { _ in throw URLError(code) }
            await assertThrows(expected, "kod \(code.rawValue)") { _ = try await TestSupport.client().status() }
        }
    }

    func testCertificateErrorIsMapped() async {
        MockURLProtocol.handler = { _ in throw URLError(.serverCertificateUntrusted) }
        do {
            _ = try await TestSupport.client().status()
            XCTFail("Oczekiwano błędu")
        } catch let APIError.certificate(detail) {
            XCTAssertFalse(detail.isEmpty)
        } catch {
            XCTFail("Zły błąd: \(error)")
        }
    }

    func testInvalidJSONGivesDecodingError() async {
        MockURLProtocol.handler = { TestSupport.respond(json: "not json", for: $0) }
        do {
            _ = try await TestSupport.client().status()
            XCTFail("Oczekiwano błędu")
        } catch APIError.decoding {
            // OK
        } catch {
            XCTFail("Zły błąd: \(error)")
        }
    }

    func testDiagnosticsContainTailscaleHints() {
        let hints = APIError.hostUnreachable.diagnostics
        XCTAssertTrue(hints.contains("Sprawdź, czy iPhone jest połączony z Tailscale"))
        XCTAssertTrue(hints.contains("Sprawdź, czy Raspberry Pi jest online w panelu Tailscale"))
        XCTAssertTrue(hints.contains("Sprawdź, czy AdGuard Home działa i jaki ma port panelu (często 80 lub 3000)"))
        XCTAssertTrue(hints.contains("Sprawdź, czy adres i port są poprawne"))
        XCTAssertTrue(APIError.unauthorized.diagnostics.first?.contains("login") == true)
    }

    // MARK: Wymagaj Tailscale

    func testRequireTailscaleBlocksRequestWhenInactive() async {
        MockURLProtocol.handler = { TestSupport.respond(json: "{}", for: $0) }
        await assertThrows(.tailscaleRequired) {
            _ = try await TestSupport.client(requireTailscale: true, tailscaleActive: false).status()
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty, "Żądanie nie powinno opuścić aplikacji")
    }

    func testRequireTailscaleAllowsRequestWhenActive() async throws {
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v1"}"#, for: $0) }
        _ = try await TestSupport.client(requireTailscale: true, tailscaleActive: true).status()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testWithoutRequireTailscaleWorksWhenInactive() async throws {
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v1"}"#, for: $0) }
        _ = try await TestSupport.client(requireTailscale: false, tailscaleActive: false).status()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    // MARK: Przełączanie ochrony

    func testEnableProtectionBody() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setProtection(enabled: true, durationMs: 5000)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/control/protection")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["enabled"] as? Bool, true)
        XCTAssertNil(body["duration"], "Czas pauzy ma sens tylko przy wyłączaniu")
    }

    func testPauseProtectionSendsDuration() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setProtection(enabled: false, durationMs: 600_000)
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["enabled"] as? Bool, false)
        XCTAssertEqual(body["duration"] as? Int, 600_000)
    }

    func testDisableProtectionWithoutDuration() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setProtection(enabled: false)
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["enabled"] as? Bool, false)
        XCTAssertNil(body["duration"])
    }

    func testSafeBrowsingAndParentalUseEnableDisableEndpoints() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        let client = TestSupport.client()
        try await client.setSafeBrowsing(true)
        try await client.setSafeBrowsing(false)
        try await client.setParental(true)
        try await client.setParental(false)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url!.path },
                       ["/control/safebrowsing/enable", "/control/safebrowsing/disable",
                        "/control/parental/enable", "/control/parental/disable"])
        XCTAssertTrue(MockURLProtocol.requests.allSatisfy { $0.httpMethod == "POST" })
    }

    func testSafeSearchSettingsUsesPUT() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setSafeSearch(SafeSearchConfig(enabled: true, bing: true, google: false))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/control/safesearch/settings")
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["enabled"] as? Bool, true)
        XCTAssertEqual(body["google"] as? Bool, false)
    }

    // MARK: Filtry i reguły

    func testAddFilterListBody() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().addFilter(name: "Moja lista", url: "https://example.org/list.txt", whitelist: false)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/control/filtering/add_url")
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["name"] as? String, "Moja lista")
        XCTAssertEqual(body["url"] as? String, "https://example.org/list.txt")
        XCTAssertEqual(body["whitelist"] as? Bool, false)
    }

    func testUpdateFilterListBodyNestsData() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().updateFilter(url: "https://old", name: "Nowa", newURL: "https://new", enabled: false, whitelist: true)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/control/filtering/set_url")
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["url"] as? String, "https://old")
        XCTAssertEqual(body["whitelist"] as? Bool, true)
        let data = try XCTUnwrap(body["data"] as? [String: Any])
        XCTAssertEqual(data["name"] as? String, "Nowa")
        XCTAssertEqual(data["url"] as? String, "https://new")
        XCTAssertEqual(data["enabled"] as? Bool, false)
    }

    func testRemoveAndRefreshFilter() async throws {
        MockURLProtocol.handler = { request in
            TestSupport.respond(json: request.url?.path.hasSuffix("refresh") == true ? #"{"updated":3}"# : "", for: request)
        }
        let client = TestSupport.client()
        try await client.removeFilter(url: "https://x", whitelist: false)
        let updated = try await client.refreshFilters(whitelist: false)
        XCTAssertEqual(updated, 3)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url!.path }, ["/control/filtering/remove_url", "/control/filtering/refresh"])
        XCTAssertEqual(TestSupport.jsonBody(0)?["url"] as? String, "https://x")
    }

    func testSetUserRulesSendsRulesArray() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setUserRules(["||ads.example.com^", "# komentarz", "@@||ok.example.com^"])
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/control/filtering/set_rules")
        XCTAssertEqual(TestSupport.jsonBody()?["rules"] as? [String], ["||ads.example.com^", "# komentarz", "@@||ok.example.com^"])
    }

    func testFilteringConfigUsesSnakeCaseAndOmitsNil() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        try await TestSupport.client().setFilteringConfig(FilterConfig(enabled: false, interval: nil))
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["enabled"] as? Bool, false)
        XCTAssertNil(body["interval"])
    }

    func testQueryLogParametersIncludeReasonsAndPaging() async throws {
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"oldest":"x","data":[]}"#, for: $0) }
        let params = QueryLogParams(olderThan: "2026-01-01T00:00:00Z", limit: 25, search: "example.org",
                                    reasons: QueryStatusFilter.blocked.reasons)
        _ = try await TestSupport.client().queryLog(params)
        let components = URLComponents(url: try XCTUnwrap(MockURLProtocol.requests.first?.url), resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertEqual(components?.path, "/control/querylog")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "25")
        XCTAssertEqual(items.first { $0.name == "search" }?.value, "example.org")
        XCTAssertEqual(items.first { $0.name == "older_than" }?.value, "2026-01-01T00:00:00Z")
        XCTAssertEqual(items.filter { $0.name == "reason" }.compactMap(\.value),
                       ["FilteredBlackList", "FilteredBlockedService", "FilteredInvalid"])
    }

    func testClientAndRewriteEndpoints() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        let client = TestSupport.client()
        var phone = Client.new()
        phone.name = "Telefon"
        phone.ids = ["100.64.0.9"]
        try await client.addClient(phone)
        try await client.updateClient(name: "Telefon", data: phone)
        try await client.deleteClient(name: "Telefon")
        try await client.addRewrite(RewriteEntry(domain: "nas.home", answer: "192.168.1.20", enabled: true))
        try await client.updateRewrite(target: RewriteEntry(domain: "a", answer: "b"), update: RewriteEntry(domain: "c", answer: "d"))
        XCTAssertEqual(MockURLProtocol.requests.map { "\($0.httpMethod!) \($0.url!.path)" },
                       ["POST /control/clients/add", "POST /control/clients/update", "POST /control/clients/delete",
                        "POST /control/rewrite/add", "PUT /control/rewrite/update"])
        XCTAssertEqual(TestSupport.jsonBody(1)?["name"] as? String, "Telefon")
        XCTAssertEqual((TestSupport.jsonBody(1)?["data"] as? [String: Any])?["name"] as? String, "Telefon")
        XCTAssertEqual(TestSupport.jsonBody(2)?["name"] as? String, "Telefon")
        XCTAssertEqual((TestSupport.jsonBody(4)?["target"] as? [String: Any])?["domain"] as? String, "a")
    }

    func testDNSConfigEncodesSnakeCase() async throws {
        MockURLProtocol.handler = { TestSupport.respond(for: $0) }
        var config = DNSConfig()
        config.upstreamDns = ["tls://1.1.1.1"]
        config.cacheEnabled = true
        config.ratelimitSubnetLenIpv4 = 24
        config.ednsCsEnabled = false
        try await TestSupport.client().setDNSConfig(config)
        let body = try XCTUnwrap(TestSupport.jsonBody())
        XCTAssertEqual(body["upstream_dns"] as? [String], ["tls://1.1.1.1"])
        XCTAssertEqual(body["cache_enabled"] as? Bool, true)
        XCTAssertEqual(body["ratelimit_subnet_len_ipv4"] as? Int, 24)
        XCTAssertEqual(body["edns_cs_enabled"] as? Bool, false)
        XCTAssertNil(body["protection_enabled"])
    }

    // MARK: Pomocnik

    private func assertThrows(_ expected: APIError, _ message: String = "", file: StaticString = #filePath, line: UInt = #line,
                              _ work: () async throws -> Void) async {
        do {
            try await work()
            XCTFail("Oczekiwano błędu \(expected) \(message)", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("Zły typ błędu: \(error)", file: file, line: line)
        }
    }
}
