import XCTest
@testable import AdGuardControl

final class ValidatorTests: XCTestCase {
    func testIPAddresses() {
        XCTAssertTrue(Validators.isIPv4("192.168.1.10"))
        XCTAssertFalse(Validators.isIPv4("192.168.1.256"))
        XCTAssertFalse(Validators.isIPv4("192.168.1"))
        XCTAssertTrue(Validators.isIPv6("fd7a:115c:a1e0::1"))
        XCTAssertFalse(Validators.isIPv6("fd7a::zz"))
        XCTAssertTrue(Validators.isIPAddress("::1"))
    }

    func testMAC() {
        XCTAssertTrue(Validators.isMAC("aa:bb:cc:dd:ee:ff"))
        XCTAssertTrue(Validators.isMAC("AA-BB-CC-DD-EE-FF"))
        XCTAssertFalse(Validators.isMAC("aa:bb:cc:dd:ee"))
        XCTAssertFalse(Validators.isMAC("aa:bb:cc:dd:ee:gg"))
        XCTAssertNil(Validators.macError(""))
        XCTAssertNotNil(Validators.macError("xyz"))
    }

    func testDomainsAndRewrites() {
        XCTAssertTrue(Validators.isDomain("nas.home"))
        XCTAssertTrue(Validators.isDomain("*.example.org"))
        XCTAssertFalse(Validators.isDomain("bad domain"))
        XCTAssertFalse(Validators.isDomain(".example.org"))
        XCTAssertFalse(Validators.isDomain("a..b"))
        XCTAssertNil(Validators.rewriteAnswerError("192.168.1.20"))
        XCTAssertNil(Validators.rewriteAnswerError("alias.example.org"))
        XCTAssertNil(Validators.rewriteAnswerError("A"))
        XCTAssertNotNil(Validators.rewriteAnswerError("300.1.1.1"), "Wygląda jak IP, ale jest błędne")
        XCTAssertNotNil(Validators.rewriteDomainError("bad domain"))
        XCTAssertNil(Validators.rewriteDomainError(""))
    }

    func testFilterURLs() {
        XCTAssertNil(Validators.filterURLError("https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"))
        XCTAssertNil(Validators.filterURLError("/opt/lists/my.txt"))
        XCTAssertNotNil(Validators.filterURLError("ftp://example.org/list.txt"))
        XCTAssertNotNil(Validators.filterURLError("not a url"))
        XCTAssertNil(Validators.filterURLError(""))
    }

    func testClientIdentifiers() {
        for good in ["192.168.1.5", "192.168.1.0/24", "fd00::/64", "aa:bb:cc:dd:ee:ff", "my-phone-1"] {
            XCTAssertTrue(Validators.isClientID(good), good)
        }
        for bad in ["192.168.1.0/33", "bad id", "a/b/c", "x_y"] {
            XCTAssertFalse(Validators.isClientID(bad), bad)
        }
        XCTAssertNil(Validators.clientIDsError(["192.168.1.5", "tablet"]))
        XCTAssertTrue(Validators.clientIDsError(["192.168.1.5", "bad id"])?.contains("bad id") == true)
    }

    func testStaticLeaseFields() {
        XCTAssertNil(Validators.ipError("192.168.1.50"))
        XCTAssertNotNil(Validators.ipError("192.168.1.500"))
        XCTAssertNil(Validators.hostnameError("nas"))
        XCTAssertNotNil(Validators.hostnameError("my nas"))
    }
}

@MainActor
final class SettingsConflictTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    func testTLSSaveDetectsServerSideChange() async throws {
        let app = try TestSupport.makeApp()
        var serverName = "a.example.org"
        MockURLProtocol.handler = { request in
            if request.url?.path == "/control/tls/status" {
                return TestSupport.respond(json: "{\"enabled\":false,\"server_name\":\"\(serverName)\"}", for: request)
            }
            return TestSupport.respond(json: "{}", for: request)
        }
        let vm = TLSViewModel()
        vm.bind(app)
        await vm.refresh()
        vm.config.serverName = "mine.example.org"

        serverName = "other.example.org"
        let saved = await vm.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(TestSupport.count(path: "/control/tls/configure"), 0, "Przy konflikcie nic nie jest zapisywane")
        XCTAssertEqual(app.toast?.style, .error)
        XCTAssertEqual(vm.config.serverName, "other.example.org")
    }

    func testTLSSaveWithoutConflictWrites() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { request in
            TestSupport.respond(json: "{\"enabled\":false,\"server_name\":\"a.example.org\"}", for: request)
        }
        let vm = TLSViewModel()
        vm.bind(app)
        await vm.refresh()
        vm.config.serverName = "mine.example.org"
        let saved = await vm.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(TestSupport.count(path: "/control/tls/configure"), 1)
    }

    func testAccessListSaveDetectsServerSideChange() async throws {
        let app = try TestSupport.makeApp()
        var disallowed = "[]"
        MockURLProtocol.handler = { request in
            if request.url?.path == "/control/access/list" {
                return TestSupport.respond(json: "{\"allowed_clients\":[],\"disallowed_clients\":\(disallowed),\"blocked_hosts\":[]}", for: request)
            }
            return TestSupport.respond(json: "{}", for: request)
        }
        let vm = AccessViewModel()
        vm.bind(app)
        await vm.refresh()
        disallowed = #"["9.9.9.9"]"#     // ktoś zablokował klienta po wczytaniu listy
        let saved = await vm.save(AccessList(allowedClients: [], disallowedClients: ["1.1.1.1"], blockedHosts: []))
        XCTAssertFalse(saved)
        XCTAssertEqual(TestSupport.count(path: "/control/access/set"), 0)
        XCTAssertEqual(vm.list.disallowed, ["9.9.9.9"])
    }
}
