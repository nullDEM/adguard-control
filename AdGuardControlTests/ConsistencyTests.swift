import XCTest
@testable import AdGuardControl

// MARK: - Cache odpowiedzi

final class ResponseCacheTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    func testCacheEntriesExpire() {
        let cache = ResponseCache()
        let start = Date()
        cache.store(Data("x".utf8), for: "k", ttl: 5, now: start)
        XCTAssertNotNil(cache.data(for: "k", now: start.addingTimeInterval(4)))
        XCTAssertNil(cache.data(for: "k", now: start.addingTimeInterval(6)))
        XCTAssertEqual(cache.count, 0, "Wygasły wpis jest usuwany")
    }

    func testStatusIsCachedWithinTTLAndClearedByWrites() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v1"}"#, for: $0) }
        let client = TestSupport.client()
        _ = try await client.status()
        _ = try await client.status()
        XCTAssertEqual(TestSupport.count(path: "/control/status"), 1, "Drugi odczyt pochodzi z cache")

        try await client.setProtection(enabled: true)
        _ = try await client.status()
        XCTAssertEqual(TestSupport.count(path: "/control/status"), 2, "Zapis unieważnia cache")

        client.invalidateCache()
        _ = try await client.status()
        XCTAssertEqual(TestSupport.count(path: "/control/status"), 3)
    }

    func testStatsCacheKeyIncludesRangeParameter() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"num_dns_queries":1}"#, for: $0) }
        let client = TestSupport.client()
        _ = try await client.stats()
        _ = try await client.stats(recentMs: 3_600_000)
        _ = try await client.stats(recentMs: 3_600_000)
        XCTAssertEqual(TestSupport.count(path: "/control/stats"), 2)
    }

    func testBlockedServicesCatalogIsDownloadedOnce() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"blocked_services":[],"groups":[]}"#, for: $0) }
        let client = TestSupport.client()
        for _ in 0..<3 { _ = try await client.allBlockedServices() }
        XCTAssertEqual(TestSupport.count(path: "/control/blocked_services/all"), 1)
    }

    func testConfigurationReadsForConflictChecksAreNeverCached() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"enabled":true,"interval":24}"#, for: $0) }
        let client = TestSupport.client()
        _ = try await client.filteringStatus()
        _ = try await client.filteringStatus()
        XCTAssertEqual(TestSupport.count(path: "/control/filtering/status"), 2)
    }
}

// MARK: - Operacje „odczytaj → zmień → zapisz”

final class MergeOperationTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    func testUpdateFilteringConfigKeepsOtherFields() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"enabled":true,"interval":12}"#, for: $0) }
        let previous = try await TestSupport.client().updateFilteringConfig(enabled: false)
        XCTAssertEqual(previous, FilterConfig(enabled: true, interval: 12))
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/filtering/config"))
        XCTAssertEqual(TestSupport.jsonBody(index)?["enabled"] as? Bool, false)
        XCTAssertEqual(TestSupport.jsonBody(index)?["interval"] as? Int, 12, "Interwał z serwera nie może zostać nadpisany")
    }

    func testModifyUserRulesWorksOnFreshRulesAndSkipsNoOps() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"user_rules":["a","b"]}"#, for: $0) }
        let client = TestSupport.client()
        let previous = try await client.modifyUserRules { $0 + ["c"] }
        XCTAssertEqual(previous, ["a", "b"])
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/filtering/set_rules"))
        XCTAssertEqual(TestSupport.jsonBody(index)?["rules"] as? [String], ["a", "b", "c"])

        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"user_rules":["a"]}"#, for: $0) }
        try await client.modifyUserRules { _ in nil }
        XCTAssertEqual(TestSupport.count(path: "/control/filtering/set_rules"), 0)
    }

    func testModifyAccessListUsesFreshList() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"allowed_clients":["1.1.1.1"],"disallowed_clients":[],"blocked_hosts":["x.org"]}"#, for: $0) }
        try await TestSupport.client().modifyAccessList { $0.disallowedClients = ["2.2.2.2"] }
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/access/set"))
        let body = try XCTUnwrap(TestSupport.jsonBody(index))
        XCTAssertEqual(body["allowed_clients"] as? [String], ["1.1.1.1"], "Pozostałe pola listy dostępu muszą zostać zachowane")
        XCTAssertEqual(body["blocked_hosts"] as? [String], ["x.org"])
        XCTAssertEqual(body["disallowed_clients"] as? [String], ["2.2.2.2"])
    }
}

// MARK: - ViewModele: aktualne dane, konflikty, odświeżanie, debounce

@MainActor
final class ConsistencyViewModelTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    private func filteringHandler(rules: @escaping () -> [String]) {
        MockURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/control/filtering/status":
                let list = rules().map { "\"\($0)\"" }.joined(separator: ",")
                return TestSupport.respond(json: "{\"enabled\":true,\"interval\":24,\"user_rules\":[\(list)]}", for: request)
            case "/control/rewrite/list": return TestSupport.respond(json: "[]", for: request)
            case "/control/rewrite/settings": return TestSupport.respond(json: #"{"enabled":true}"#, for: request)
            default: return TestSupport.respond(json: "{}", for: request)
            }
        }
    }

    func testDeletingRuleTargetsRuleByTextNotStaleIndex() async throws {
        let app = try TestSupport.makeApp()
        var serverRules = ["||x.com^", "||y.com^"]
        filteringHandler { serverRules }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        let target = try XCTUnwrap(vm.userRules.first { $0.text == "||x.com^" })
        XCTAssertEqual(target.id, 0)

        // Ktoś dodał regułę na początku listy (np. szybkie blokowanie z Query Log).
        serverRules = ["||new.com^", "||x.com^", "||y.com^"]
        await vm.deleteRule(target)

        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/filtering/set_rules"))
        XCTAssertEqual(TestSupport.jsonBody(index)?["rules"] as? [String], ["||new.com^", "||y.com^"])
    }

    func testRuleChangedOnServerGivesConflictAndWritesNothing() async throws {
        let app = try TestSupport.makeApp()
        var serverRules = ["||x.com^"]
        filteringHandler { serverRules }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        let target = try XCTUnwrap(vm.userRules.first)

        serverRules = ["||other.com^"]
        await vm.deleteRule(target)

        XCTAssertEqual(TestSupport.count(path: "/control/filtering/set_rules"), 0)
        XCTAssertEqual(app.toast?.style, .error)
        XCTAssertEqual(vm.userRuleLines, ["||other.com^"], "Dane powinny zostać odświeżone po konflikcie")
    }

    func testTogglingRuleKeepsRulesAddedMeanwhile() async throws {
        let app = try TestSupport.makeApp()
        var serverRules = ["||x.com^"]
        filteringHandler { serverRules }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        let target = try XCTUnwrap(vm.userRules.first)
        serverRules = ["||x.com^", "@@||ok.com^"]
        await vm.toggleRule(target)
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/filtering/set_rules"))
        XCTAssertEqual(TestSupport.jsonBody(index)?["rules"] as? [String], ["! ||x.com^", "@@||ok.com^"])
    }

    func testBlockingClientUsesFreshAccessList() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { request in
            if request.url?.path == "/control/access/list" {
                return TestSupport.respond(json: #"{"allowed_clients":[],"disallowed_clients":["1.1.1.1"],"blocked_hosts":[]}"#, for: request)
            }
            return TestSupport.respond(json: "{}", for: request)
        }
        let vm = ClientsViewModel()
        vm.bind(app)
        XCTAssertTrue(vm.access.disallowed.isEmpty, "Lokalna kopia jest pusta (nieaktualna)")
        await vm.setBlocked(ids: ["2.2.2.2"], blocked: true, label: "2.2.2.2")
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/access/set"))
        XCTAssertEqual(TestSupport.jsonBody(index)?["disallowed_clients"] as? [String], ["1.1.1.1", "2.2.2.2"])
    }

    private static let dnsJSON = """
    {"upstream_dns":["%@"],"bootstrap_dns":["9.9.9.10"],"fallback_dns":[],"protection_enabled":true,
     "blocking_mode":"default","cache_enabled":true,"cache_size":4194304,"upstream_mode":"load_balance",
     "local_ptr_upstreams":[],"default_local_ptr_upstreams":[]}
    """

    func testDNSSaveDetectsServerSideChange() async throws {
        let app = try TestSupport.makeApp()
        var upstream = "1.1.1.1"
        MockURLProtocol.handler = { request in
            if request.url?.path == "/control/dns_info" {
                return TestSupport.respond(json: String(format: Self.dnsJSON, upstream), for: request)
            }
            return TestSupport.respond(json: "{}", for: request)
        }
        let vm = DNSViewModel()
        vm.bind(app)
        await vm.refresh()
        vm.config.upstreamDns = ["8.8.8.8"]

        upstream = "9.9.9.9"        // zmiana na serwerze po wczytaniu
        let saved = await vm.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(TestSupport.count(path: "/control/dns_config"), 0, "Przy konflikcie nic nie jest zapisywane")
        XCTAssertEqual(app.toast?.style, .error)
        XCTAssertEqual(vm.config.upstreamDns, ["9.9.9.9"], "Dane odświeżone do stanu serwera")
    }

    func testDNSSaveWithoutConflictWritesWithoutProtectionFields() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { request in
            if request.url?.path == "/control/dns_info" {
                return TestSupport.respond(json: String(format: Self.dnsJSON, "1.1.1.1"), for: request)
            }
            return TestSupport.respond(json: "{}", for: request)
        }
        let vm = DNSViewModel()
        vm.bind(app)
        await vm.refresh()
        vm.config.upstreamDns = ["8.8.8.8"]
        let saved = await vm.save()
        XCTAssertTrue(saved)
        let index = try XCTUnwrap(TestSupport.lastIndex(path: "/control/dns_config"))
        let body = try XCTUnwrap(TestSupport.jsonBody(index))
        XCTAssertEqual(body["upstream_dns"] as? [String], ["8.8.8.8"])
        XCTAssertNil(body["protection_enabled"], "Stan ochrony zmienia osobny endpoint")
    }

    func testDHCPSaveDetectsServerSideChange() async throws {
        let app = try TestSupport.makeApp()
        var rangeEnd = "192.168.1.200"
        MockURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/control/dhcp/status":
                return TestSupport.respond(json: """
                {"enabled":false,"interface_name":"eth0","v4":{"gateway_ip":"192.168.1.1","subnet_mask":"255.255.255.0",
                 "range_start":"192.168.1.100","range_end":"\(rangeEnd)","lease_duration":86400},"leases":[],"static_leases":[]}
                """, for: request)
            case "/control/dhcp/interfaces": return TestSupport.respond(json: "{}", for: request)
            default: return TestSupport.respond(json: "{}", for: request)
            }
        }
        let vm = DHCPViewModel()
        vm.bind(app)
        await vm.refresh()
        vm.draft.enabled = true

        rangeEnd = "192.168.1.150"
        let saved = await vm.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(TestSupport.count(path: "/control/dhcp/set_config"), 0)
        XCTAssertEqual(app.toast?.style, .error)
    }

    // MARK: Odświeżanie warunkowe

    func testRefreshIfNeededSkipsFreshDataButManualRefreshAlwaysFetches() async throws {
        let app = try TestSupport.makeApp()
        filteringHandler { [] }
        let vm = FiltersViewModel()
        vm.bind(app)
        XCTAssertTrue(vm.needsRefresh(), "Brak danych – trzeba pobrać")
        await vm.refreshIfNeeded()
        let afterFirst = TestSupport.count(path: "/control/filtering/status")
        XCTAssertEqual(afterFirst, 1)

        await vm.refreshIfNeeded()
        XCTAssertEqual(TestSupport.count(path: "/control/filtering/status"), afterFirst, "Świeże dane – bez zapytań")
        XCTAssertFalse(vm.needsRefresh())
        XCTAssertTrue(vm.needsRefresh(now: Date().addingTimeInterval(60)), "Po 60 s dane są nieaktualne")

        await vm.refresh()
        XCTAssertEqual(TestSupport.count(path: "/control/filtering/status"), afterFirst + 1, "Ręczne odświeżenie zawsze pobiera")
    }

    func testFailedStateAlwaysNeedsRefreshSoReconnectRetries() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refreshIfNeeded()
        XCTAssertEqual(vm.state, .failed(.noConnection))
        XCTAssertTrue(vm.needsRefresh(), "Po błędzie następny sygnał (powrót sieci) musi ponowić pobieranie")

        filteringHandler { [] }
        app.requestRefresh()
        await vm.refreshIfNeeded()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(app.refreshTrigger, 1)
    }

    func testTailscaleRequiredStateWhenVPNOff() async throws {
        MockURLProtocol.reset()
        let defaults = UserDefaults(suiteName: "ts.\(UUID().uuidString)")!
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: false), sessionFactory: { TestSupport.session() })
        var profile = ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "a")
        profile.requireTailscale = true
        try app.save(profile: profile, password: "p")
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertEqual(vm.state, .failed(.tailscaleRequired))
        XCTAssertTrue(MockURLProtocol.requests.isEmpty, "Bez Tailscale nie wolno wysłać żadnego zapytania")
    }

    // MARK: Utrata połączenia w trakcie operacji

    func testConnectionLostDuringMutationShowsErrorAndKeepsData() async throws {
        let app = try TestSupport.makeApp()
        filteringHandler { ["||x.com^"] }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        let before = vm.userRuleLines

        MockURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        let ok = await vm.addRule("||new.com^")
        XCTAssertFalse(ok)
        XCTAssertEqual(app.toast?.style, .error)
        XCTAssertEqual(vm.userRuleLines, before, "Dane nie mogą się zmienić po nieudanym zapisie")
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertFalse(vm.isBusy)
    }

    func testTimeoutAndWrongPortAreMappedToReadableErrors() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertEqual(vm.state, .failed(.timeout))

        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        await vm.refresh()
        XCTAssertEqual(vm.state, .failed(.hostUnreachable))
        XCTAssertTrue(APIError.hostUnreachable.diagnostics.contains { $0.contains("port") })
    }

    func testWrongPasswordGivesUnauthorizedState() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { TestSupport.respond(status: 401, json: "Unauthorized", for: $0) }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertEqual(vm.state, .failed(.unauthorized))
        XCTAssertTrue(APIError.unauthorized.isAuthorizationProblem)
    }
}

// MARK: - Query log: debounce, filtry lokalne, długa lista

@MainActor
final class QueryLogBehaviorTests: XCTestCase {
    override func tearDown() {
        QueryLogViewModel.searchDebounce = .milliseconds(350)
        MockURLProtocol.reset()
    }

    private func entry(_ index: Int, client: String = "192.168.1.5", time: String = "2026-10-20T10:00:00Z") -> String {
        """
        {"answer":[],"client":"\(client)","elapsedMs":"1.2","question":{"class":"IN","name":"host\(index).example.com","type":"A"},
         "reason":"NotFilteredNotFound","status":"NOERROR","time":"\(time)"}
        """
    }

    func testSearchIsDebouncedIntoSingleRequest() async throws {
        let app = try TestSupport.makeApp()
        QueryLogViewModel.searchDebounce = .milliseconds(60)
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"data":[],"oldest":""}"#, for: $0) }
        let vm = QueryLogViewModel()
        vm.bind(app)
        for text in ["g", "go", "goo", "goog"] {
            vm.search = text
            vm.searchTextChanged()
        }
        try await Task.sleep(for: .milliseconds(400))
        let requests = MockURLProtocol.requests.filter { $0.url?.path == "/control/querylog" }
        XCTAssertEqual(requests.count, 1, "Cztery naciśnięcia klawiszy = jedno zapytanie")
        XCTAssertTrue(requests.first?.url?.query?.contains("search=goog") == true)
    }

    func testSubmitSearchSkipsDebounce() async throws {
        let app = try TestSupport.makeApp()
        QueryLogViewModel.searchDebounce = .seconds(5)
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"data":[],"oldest":""}"#, for: $0) }
        let vm = QueryLogViewModel()
        vm.bind(app)
        vm.search = "abc"
        vm.searchTextChanged()
        await vm.submitSearch()
        XCTAssertEqual(TestSupport.count(path: "/control/querylog"), 1)
    }

    func testStalePageIsDroppedAfterFilterChange() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { request in
            let page = (0..<QueryLogViewModel.pageSize).map { self.entry($0) }.joined(separator: ",")
            return TestSupport.respond(json: "{\"data\":[\(page)],\"oldest\":\"2026-10-20T09:00:00Z\"}", for: request)
        }
        let vm = QueryLogViewModel()
        vm.bind(app)
        await vm.reload()
        XCTAssertEqual(vm.items.count, QueryLogViewModel.pageSize)
        XCTAssertTrue(vm.canLoadMore)

        let loading = Task { await vm.loadMore() }
        await Task.yield()              // loadMore wysłał zapytanie i czeka na odpowiedź
        vm.search = "other"
        await vm.reload()               // nowe zapytanie zastępuje poprzedni stan
        await loading.value
        XCTAssertEqual(vm.items.count, QueryLogViewModel.pageSize, "Strona ze starego zapytania nie może trafić do nowej listy")
    }

    func testLoadMoreIsIgnoredWhileReloading() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { request in
            let page = (0..<QueryLogViewModel.pageSize).map { self.entry($0) }.joined(separator: ",")
            return TestSupport.respond(json: "{\"data\":[\(page)],\"oldest\":\"2026-10-20T09:00:00Z\"}", for: request)
        }
        let vm = QueryLogViewModel()
        vm.bind(app)
        await vm.reload()
        let reloading = Task { await vm.reload() }
        await Task.yield()
        await vm.loadMore()             // w trakcie przeładowania – ma zostać pominięte
        await reloading.value
        XCTAssertEqual(vm.items.count, QueryLogViewModel.pageSize)
    }

    func testLocalFiltersAndVeryLongList() async throws {
        let app = try TestSupport.makeApp()
        let count = 3000
        MockURLProtocol.handler = { request in
            let items = (0..<count).map { self.entry($0, client: $0 % 3 == 0 ? "10.0.0.1" : "10.0.0.2") }.joined(separator: ",")
            return TestSupport.respond(json: "{\"data\":[\(items)],\"oldest\":\"\"}", for: request)
        }
        let vm = QueryLogViewModel()
        vm.bind(app)
        let started = Date()
        await vm.reload()
        XCTAssertEqual(vm.items.count, count)
        XCTAssertEqual(vm.visibleItems.count, count)
        vm.clientFilter = "10.0.0.1"
        XCTAssertEqual(vm.visibleItems.count, count / 3)
        vm.timeRange = .hour                 // wpisy z 2026-10-20T10:00Z są starsze niż godzina
        XCTAssertEqual(vm.visibleItems.count, 0)
        vm.timeRange = .all
        vm.clientFilter = ""
        XCTAssertEqual(vm.visibleItems.count, count)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "3000 wpisów musi się wczytać i przefiltrować szybko")
    }

    func testEmptyQueryLogLoadsToEmptyList() async throws {
        let app = try TestSupport.makeApp()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"data":[],"oldest":""}"#, for: $0) }
        let vm = QueryLogViewModel()
        vm.bind(app)
        await vm.reload()
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertTrue(vm.visibleItems.isEmpty)
        XCTAssertFalse(vm.canLoadMore)
    }
}
