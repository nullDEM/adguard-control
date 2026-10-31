import XCTest
@testable import AdGuardControl

final class StorageTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testProfilesRoundTripWithoutPassword() throws {
        let store = ProfileStore(defaults: defaults)
        let profile = ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "admin", requireTailscale: true)
        store.save([profile])
        store.activeProfileID = profile.id

        let loaded = ProfileStore(defaults: defaults).load()
        XCTAssertEqual(loaded, [profile])
        XCTAssertEqual(ProfileStore(defaults: defaults).activeProfileID, profile.id)

        let raw = try XCTUnwrap(defaults.data(forKey: "profiles.v1"))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.lowercased().contains("password"), "Hasło nie może trafić do UserDefaults")
    }

    func testKeychainRoundTripAndDelete() throws {
        let store = KeychainStore(service: "pl.adguardcontrol.tests.\(UUID().uuidString)")
        let id = UUID()
        XCTAssertNil(store.password(for: id))
        try store.setPassword("pierwsze", for: id)
        XCTAssertEqual(store.password(for: id), "pierwsze")
        try store.setPassword("drugie", for: id)
        XCTAssertEqual(store.password(for: id), "drugie")
        store.deletePassword(for: id)
        XCTAssertNil(store.password(for: id))
    }

    func testKeychainMigrationKeepsPasswordsAndRunsOnlyOnce() throws {
        let store = KeychainStore(service: "pl.adguardcontrol.tests.\(UUID().uuidString)")
        let suite = "pl.adguardcontrol.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        try store.setPassword("tajne", for: id)

        store.migrateToSharedGroup(profileIDs: [id], defaults: defaults)
        XCTAssertEqual(store.password(for: id), "tajne", "migracja nie może zgubić hasła")

        // Po pomyślnej migracji flaga blokuje kolejne przebiegi (nie przepisujemy haseł przy każdym starcie).
        store.deletePassword(for: id)
        store.migrateToSharedGroup(profileIDs: [id], defaults: defaults)
        XCTAssertNil(store.password(for: id))
        store.deletePassword(for: id)
    }

    func testInMemoryStoreMigrationIsANoOp() throws {
        let store = InMemoryPasswordStore()
        let id = UUID()
        try store.setPassword("a", for: id)
        store.migrateToSharedGroup(profileIDs: [id])
        XCTAssertEqual(store.password(for: id), "a")
    }

    func testToggleConfirmationOnlyAsksForTheRiskyDirection() {
        XCTAssertFalse(ToggleConfirmation.none.requiresConfirmation(settingTo: true))
        XCTAssertFalse(ToggleConfirmation.none.requiresConfirmation(settingTo: false))
        XCTAssertTrue(ToggleConfirmation.whenTurningOff.requiresConfirmation(settingTo: false))
        XCTAssertFalse(ToggleConfirmation.whenTurningOff.requiresConfirmation(settingTo: true))
        XCTAssertTrue(ToggleConfirmation.whenTurningOn.requiresConfirmation(settingTo: true))
        XCTAssertFalse(ToggleConfirmation.whenTurningOn.requiresConfirmation(settingTo: false))
    }

    @MainActor
    func testAppStateSavesNormalizedProfileAndKeepsPasswordOutOfDefaults() throws {
        let passwords = InMemoryPasswordStore()
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: passwords,
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        XCTAssertTrue(app.profiles.isEmpty)

        let profile = ServerProfile(name: "Pi", address: "ADGUARD-home:3000/control/", username: "admin")
        try app.save(profile: profile, password: "tajne")

        XCTAssertEqual(app.profiles.first?.address, "http://adguard-home:3000")
        XCTAssertEqual(app.activeProfileID, profile.id)
        XCTAssertEqual(passwords.password(for: profile.id), "tajne")
        let stored = String(decoding: defaults.data(forKey: "profiles.v1") ?? Data(), as: UTF8.self)
        XCTAssertFalse(stored.contains("tajne"))
    }

    @MainActor
    func testMultipleProfilesSwitchAndDelete() throws {
        let passwords = InMemoryPasswordStore()
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: passwords,
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        let first = ServerProfile(name: "Dom", address: "http://192.168.1.10:3000", username: "a")
        let second = ServerProfile(name: "Biuro", address: "http://100.64.0.7:3000", username: "b")
        try app.save(profile: first, password: "1")
        try app.save(profile: second, password: "2")
        XCTAssertEqual(app.activeProfileID, first.id)

        app.select(second.id)
        XCTAssertEqual(app.api?.baseURL.absoluteString, "http://100.64.0.7:3000")
        app.select(first.id)
        XCTAssertEqual(app.api?.baseURL.absoluteString, "http://192.168.1.10:3000")

        app.delete(first)
        XCTAssertEqual(app.profiles, [second])
        XCTAssertEqual(app.activeProfileID, second.id)
        XCTAssertNil(passwords.password(for: first.id))
        app.delete(second)
        XCTAssertNil(app.activeProfileID)
        XCTAssertNil(app.api)
    }

    @MainActor
    func testConnectionTestUsesProvidedCredentialsWithoutSaving() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { TestSupport.respond(json: #"{"protection_enabled":true,"version":"v0.107.50"}"#, for: $0) }
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        let status = try await app.testConnection(address: "192.168.1.10:3000", username: "admin", password: "pw", requireTailscale: false)
        XCTAssertEqual(status.version, "v0.107.50")
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.absoluteString, "http://192.168.1.10:3000/control/status")
        XCTAssertEqual(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"),
                       AdGuardAPIClient.basicAuthHeader(username: "admin", password: "pw"))
        XCTAssertTrue(app.profiles.isEmpty)

        MockURLProtocol.handler = { TestSupport.respond(status: 401, for: $0) }
        do {
            _ = try await app.testConnection(address: "192.168.1.10:3000", username: "admin", password: "zle", requireTailscale: false)
            XCTFail("Oczekiwano 401")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        MockURLProtocol.reset()
    }
}

final class UserRulesTests: XCTestCase {
    func testClassifiesRules() {
        let rules = UserRule.parse(["||ads.com^", "@@||ok.com^", "# komentarz", "! ||wylaczona.com^", "", "  "])
        XCTAssertEqual(rules.map(\.kind), [.block, .allow, .comment, .disabled])
        XCTAssertEqual(rules.map(\.id), [0, 1, 2, 3], "Indeks to numer linii w oryginalnej liście")
        XCTAssertEqual(rules.map(\.isEnabled), [true, true, false, false])
    }

    func testToggleDisablesAndEnablesRule() {
        let rule = UserRule(id: 0, text: "||ads.com^")
        let disabled = UserRule(id: 0, text: rule.toggled())
        XCTAssertEqual(disabled.text, "! ||ads.com^")
        XCTAssertEqual(disabled.kind, .disabled)
        XCTAssertEqual(UserRule(id: 0, text: disabled.toggled()).text, "||ads.com^")
    }

    func testRuleBuilders() {
        XCTAssertEqual(UserRule.blockRule(domain: "example.org"), "||example.org^")
        XCTAssertEqual(UserRule.allowRule(domain: "example.org"), "@@||example.org^")
    }
}

@MainActor
final class ViewModelTests: XCTestCase {
    private func makeApp() throws -> AppState {
        MockURLProtocol.reset()
        let defaults = UserDefaults(suiteName: "vm.\(UUID().uuidString)")!
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        try app.save(profile: ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "admin"), password: "pw")
        return app
    }

    override func tearDown() { MockURLProtocol.reset() }

    func testProtectionViewModelTogglesAndShowsUndo() async throws {
        let app = try makeApp()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json: String
            switch path {
            case "/control/status": json = #"{"protection_enabled":false,"version":"v1"}"#
            case "/control/filtering/status": json = #"{"enabled":true,"interval":24}"#
            case "/control/safebrowsing/status": json = #"{"enabled":false}"#
            case "/control/parental/status": json = #"{"enabled":false}"#
            case "/control/safesearch/status": json = #"{"enabled":false}"#
            case "/control/blocked_services/all": json = #"{"blocked_services":[],"groups":[]}"#
            case "/control/blocked_services/get": json = #"{"ids":[]}"#
            default: json = ""
            }
            return TestSupport.respond(json: json, for: request)
        }
        let vm = ProtectionViewModel()
        vm.bind(app)
        await vm.setProtection(enabled: false, durationMs: 60_000)

        let post = try XCTUnwrap(MockURLProtocol.requests.first { $0.url?.path == "/control/protection" })
        XCTAssertEqual(post.httpMethod, "POST")
        let index = try XCTUnwrap(MockURLProtocol.requests.firstIndex { $0.url?.path == "/control/protection" })
        XCTAssertEqual(TestSupport.jsonBody(index)?["enabled"] as? Bool, false)
        XCTAssertEqual(TestSupport.jsonBody(index)?["duration"] as? Int, 60_000)
        XCTAssertNotNil(app.toast?.undo, "Po zmianie powinien być dostępny przycisk Cofnij")
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.status?.protectionEnabled, false)
    }

    func testQuickBlockAppendsRuleAndUndoRestoresPreviousRules() async throws {
        let app = try makeApp()
        MockURLProtocol.handler = { request in
            let json = request.url?.path == "/control/filtering/status" ? #"{"user_rules":["@@||ok.com^"]}"# : ""
            return TestSupport.respond(json: json, for: request)
        }
        let vm = QueryLogViewModel()
        vm.bind(app)
        await vm.blockDomain("ads.example.com")

        let setIndex = try XCTUnwrap(MockURLProtocol.requests.firstIndex { $0.url?.path == "/control/filtering/set_rules" })
        XCTAssertEqual(TestSupport.jsonBody(setIndex)?["rules"] as? [String], ["@@||ok.com^", "||ads.example.com^"])

        let undo = try XCTUnwrap(app.toast?.undo)
        await undo()
        let lastSet = try XCTUnwrap(MockURLProtocol.requests.lastIndex { $0.url?.path == "/control/filtering/set_rules" })
        XCTAssertGreaterThan(lastSet, setIndex)
        XCTAssertEqual(TestSupport.jsonBody(lastSet)?["rules"] as? [String], ["@@||ok.com^"])
    }

    func testQuickBlockDoesNotDuplicateExistingRule() async throws {
        let app = try makeApp()
        MockURLProtocol.handler = { request in
            let json = request.url?.path == "/control/filtering/status" ? #"{"user_rules":["||ads.example.com^"]}"# : ""
            return TestSupport.respond(json: json, for: request)
        }
        let vm = QueryLogViewModel()
        vm.bind(app)
        await vm.blockDomain("ads.example.com")
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.url?.path == "/control/filtering/set_rules" })
    }

    func testFiltersViewModelRuleLifecycle() async throws {
        let app = try makeApp()
        var rules = ["||a.com^", "# nota"]
        MockURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/control/filtering/status":
                let list = rules.map { "\"\($0)\"" }.joined(separator: ",")
                return TestSupport.respond(json: #"{"enabled":true,"interval":24,"filters":[],"user_rules":[\#(list)]}"#, for: request)
            case "/control/rewrite/list": return TestSupport.respond(json: "[]", for: request)
            case "/control/rewrite/settings": return TestSupport.respond(json: #"{"enabled":true}"#, for: request)
            default: return TestSupport.respond(for: request)
            }
        }
        let vm = FiltersViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertEqual(vm.userRules.map(\.text), ["||a.com^", "# nota"])

        let added = await vm.addRule("||b.com^")
        XCTAssertTrue(added)
        var setIndex = try XCTUnwrap(MockURLProtocol.requests.lastIndex { $0.url?.path == "/control/filtering/set_rules" })
        XCTAssertEqual(TestSupport.jsonBody(setIndex)?["rules"] as? [String], ["||a.com^", "# nota", "||b.com^"])

        await vm.toggleRule(vm.userRules[0])
        setIndex = try XCTUnwrap(MockURLProtocol.requests.lastIndex { $0.url?.path == "/control/filtering/set_rules" })
        XCTAssertEqual((TestSupport.jsonBody(setIndex)?["rules"] as? [String])?.first, "! ||a.com^")

        await vm.deleteRule(vm.userRules[0])
        setIndex = try XCTUnwrap(MockURLProtocol.requests.lastIndex { $0.url?.path == "/control/filtering/set_rules" })
        XCTAssertEqual(TestSupport.jsonBody(setIndex)?["rules"] as? [String], ["# nota"])
        rules = []
    }

    func testFilterListManagementCallsExpectedEndpoints() async throws {
        let app = try makeApp()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/control/filtering/status" { return TestSupport.respond(json: #"{"enabled":true,"filters":[]}"#, for: request) }
            if path == "/control/filtering/refresh" { return TestSupport.respond(json: #"{"updated":2}"#, for: request) }
            return TestSupport.respond(for: request)
        }
        let vm = FiltersViewModel()
        vm.bind(app)
        let filter = Filter(enabled: true, id: 1, lastUpdated: nil, name: "Lista", rulesCount: 10, url: "https://x/list.txt")

        let added = await vm.addFilter(name: "Lista", url: "https://x/list.txt", whitelist: false)
        XCTAssertTrue(added)
        await vm.setFilter(filter, enabled: false, whitelist: false)
        await vm.refreshFilters(whitelist: false)
        await vm.removeFilter(filter, whitelist: false)

        let paths = MockURLProtocol.requests.compactMap { $0.url?.path }.filter { $0 != "/control/filtering/status" }
        XCTAssertEqual(paths, ["/control/filtering/add_url", "/control/filtering/set_url",
                               "/control/filtering/refresh", "/control/filtering/remove_url"])
        let setIndex = try XCTUnwrap(MockURLProtocol.requests.firstIndex { $0.url?.path == "/control/filtering/set_url" })
        XCTAssertEqual((TestSupport.jsonBody(setIndex)?["data"] as? [String: Any])?["enabled"] as? Bool, false)
    }

    func testAuthorizationFailureSetsFailedState() async throws {
        let app = try makeApp()
        MockURLProtocol.handler = { TestSupport.respond(status: 401, for: $0) }
        let vm = DashboardViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertEqual(vm.state, .failed(.unauthorized))
    }
}

@MainActor
final class RegressionTests: XCTestCase {
    func testStatsRangesRespectServerRetention() {
        // retencja 24 h → bez zakresu 7 dni
        XCTAssertEqual(DashboardViewModel.ranges(retentionMs: 86_400_000), [.full, .hour, .day])
        // retencja 7 dni → wszystkie
        XCTAssertEqual(DashboardViewModel.ranges(retentionMs: 604_800_000), StatsRange.allCases)
        // retencja nieznana → wszystkie
        XCTAssertEqual(DashboardViewModel.ranges(retentionMs: nil), StatsRange.allCases)
    }

    func testDashboardHidesUnsupportedRangeAndResetsSelection() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let defaults = UserDefaults(suiteName: "reg.\(UUID().uuidString)")!
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        try app.save(profile: ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "a"), password: "p")
        MockURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/control/stats/config": return TestSupport.respond(json: #"{"enabled":true,"interval":86400000,"ignored":[]}"#, for: request)
            case "/control/status": return TestSupport.respond(json: #"{"protection_enabled":true,"version":"v1"}"#, for: request)
            case "/control/querylog": return TestSupport.respond(json: #"{"data":[]}"#, for: request)
            default: return TestSupport.respond(json: "{}", for: request)
            }
        }
        let vm = DashboardViewModel()
        vm.bind(app)
        vm.range = .week
        await vm.refresh()
        XCTAssertEqual(vm.availableRanges, [.full, .hour, .day])
        XCTAssertEqual(vm.range, .full)
        let statsRequest = try XCTUnwrap(MockURLProtocol.requests.first { $0.url?.path == "/control/stats" })
        XCTAssertNil(statsRequest.url?.query, "Dla niedostępnego zakresu nie wolno wysyłać recent=")
    }

    func testClientsRefreshDoesNotDownloadBlockedServicesCatalog() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let defaults = UserDefaults(suiteName: "reg.\(UUID().uuidString)")!
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        try app.save(profile: ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "a"), password: "p")
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let json = path == "/control/blocked_services/all" ? #"{"blocked_services":[{"id":"yt","name":"YouTube","icon_svg":"","rules":[]}],"groups":[]}"# : "{}"
            return TestSupport.respond(json: json, for: request)
        }
        let vm = ClientsViewModel()
        vm.bind(app)
        await vm.refresh()
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.url?.path == "/control/blocked_services/all" })
        await vm.loadServicesIfNeeded()
        await vm.loadServicesIfNeeded()
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.url?.path == "/control/blocked_services/all" }.count, 1, "Katalog ładowany raz")
        XCTAssertEqual(vm.availableServices.map(\.id), ["yt"])
    }

    func testLinesParsingKeepsOneEntryPerLine() {
        XCTAssertEqual(Formatting.lines("a\n\n  b  \r\nc\n"), ["a", "b", "c"])
        XCTAssertEqual(Formatting.lines("a\n9.9.9.9"), ["a", "9.9.9.9"])
    }
}
