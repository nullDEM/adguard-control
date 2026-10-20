import XCTest
@testable import AdGuardControl

final class WidgetTests: XCTestCase {
    private let statusJSON = #"{"protection_enabled":true,"version":"v0.107.79","running":true}"#
    private let statsJSON = """
    {"num_dns_queries":1000,"num_blocked_filtering":200,"num_replaced_safebrowsing":0,"num_replaced_parental":0,
     "top_blocked_domains":[{"ads.a.net":5},{"track.b.net":40}],"top_clients":[{"1.1.1.1":3}]}
    """

    private func loader(profiles: [ServerProfile], active: UUID? = nil, password: String? = "pw") -> WidgetDataLoader {
        MockURLProtocol.reset()
        return WidgetDataLoader(profiles: { profiles }, activeProfileID: { active }, password: { _ in password },
                                session: { TestSupport.session() }, tailscaleProbe: StubTailscale(active: true))
    }

    private let pi = ServerProfile(name: "Pi", address: "http://100.64.0.5:3000", username: "admin")
    private let nas = ServerProfile(name: "NAS", address: "http://192.168.1.10", username: "admin")

    func testSnapshotFromStatusAndStats() async {
        let loader = loader(profiles: [pi])
        MockURLProtocol.handler = { request in
            TestSupport.respond(json: request.url!.path.hasSuffix("/status") ? self.statusJSON : self.statsJSON, for: request)
        }
        let snapshot = await loader.load(profileID: nil)
        XCTAssertNil(snapshot.failure)
        XCTAssertEqual(snapshot.profileName, "Pi")
        XCTAssertTrue(snapshot.protectionEnabled)
        XCTAssertEqual(snapshot.totalQueries, 1000)
        XCTAssertEqual(snapshot.blockedQueries, 200)
        XCTAssertEqual(snapshot.blockedPercent, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot.topBlocked, "track.b.net")
    }

    func testProfileSelectionPrefersConfiguredThenActiveThenFirst() {
        let loader = loader(profiles: [pi, nas], active: nas.id)
        XCTAssertEqual(loader.resolveProfile(id: pi.id)?.id, pi.id)
        XCTAssertEqual(loader.resolveProfile(id: nil)?.id, nas.id)
        XCTAssertEqual(loader.resolveProfile(id: UUID())?.id, nas.id)
        XCTAssertEqual(self.loader(profiles: [pi]).resolveProfile(id: nil)?.id, pi.id)
        XCTAssertNil(self.loader(profiles: []).resolveProfile(id: nil))
    }

    func testNoProfileAndMissingPasswordGiveReadableFailures() async {
        let empty = await loader(profiles: []).load(profileID: nil)
        XCTAssertEqual(empty.failure, .noProfile)
        let noPassword = await loader(profiles: [pi], password: nil).load(profileID: nil)
        XCTAssertEqual(noPassword.failure, .other)
        XCTAssertEqual(MockURLProtocol.requests.count, 0, "bez hasła widget nie może wysyłać żądań")
    }

    func testErrorsAreMappedToWidgetFailures() async {
        let loader = loader(profiles: [pi])
        MockURLProtocol.handler = { TestSupport.respond(status: 401, json: "", for: $0) }
        let unauthorized = await loader.load(profileID: nil)
        XCTAssertEqual(unauthorized.failure, .unauthorized)

        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let timeout = await loader.load(profileID: nil)
        XCTAssertEqual(timeout.failure, .unreachable)
    }

    func testWidgetRefusesPublicCleartextAddress() async {
        let publicProfile = ServerProfile(name: "Publiczny", address: "http://8.8.8.8", username: "admin")
        let snapshot = await loader(profiles: [publicProfile]).load(profileID: nil)
        XCTAssertEqual(snapshot.failure, .other)
        XCTAssertEqual(MockURLProtocol.requests.count, 0)
    }

    func testPausedProtectionKeepsRemainingTime() {
        let status = ServerStatus(protectionEnabled: false, protectionDisabledDuration: 60_000, version: "v1")
        let snapshot = WidgetSnapshot.make(profile: pi, status: status, stats: Stats())
        XCTAssertEqual(snapshot.pausedForMs, 60_000)
        XCTAssertEqual(snapshot.stateTitleForTests, "paused")
    }

    func testToggleSendsProtectionRequestForChosenProfile() async throws {
        let loader = loader(profiles: [pi, nas])
        MockURLProtocol.handler = { TestSupport.respond(json: "", for: $0) }
        try await loader.setProtection(profileID: nas.id, enabled: false, pauseMs: 600_000)
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.host, "192.168.1.10")
        XCTAssertEqual(request.url?.path, "/control/protection")
        let body = try XCTUnwrap(TestSupport.jsonBody(0))
        XCTAssertEqual(body["enabled"] as? Bool, false)
        XCTAssertEqual(body["duration"] as? Int, 600_000)
    }

    func testDeepLinkRoundTripAndRejectsForeignURLs() throws {
        let id = UUID()
        let link = DeepLink(tab: .querylog, profileID: id)
        XCTAssertEqual(DeepLink(url: link.url), link)
        XCTAssertEqual(DeepLink(url: DeepLink(tab: .dashboard).url)?.profileID, nil)
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/open?tab=querylog")!))
        XCTAssertNil(DeepLink(url: URL(string: "adguardcontrol://open?tab=nope")!))
        XCTAssertNil(DeepLink(url: URL(string: "adguardcontrol://delete?tab=filters")!))
        XCTAssertEqual(DeepLink(url: URL(string: "adguardcontrol://open?tab=filters&profile=zepsute")!),
                       DeepLink(tab: .filters, profileID: nil))
    }

    @MainActor
    func testOpeningDeepLinkSelectsTabAndKnownProfileOnly() throws {
        let app = try TestSupport.makeApp()
        let first = try XCTUnwrap(app.activeProfileID)
        try app.save(profile: ServerProfile(name: "Drugi", address: "http://100.64.0.6:3000", username: "admin"), password: "pw")
        let second = try XCTUnwrap(app.profiles.first { $0.id != first }?.id)

        app.open(DeepLink(tab: .querylog, profileID: second))
        XCTAssertEqual(app.selectedTab, .querylog)
        XCTAssertEqual(app.activeProfileID, second)

        app.open(DeepLink(tab: .filters, profileID: UUID()))   // nieistniejący profil nie zmienia serwera
        XCTAssertEqual(app.selectedTab, .filters)
        XCTAssertEqual(app.activeProfileID, second)
    }

    func testSharedProfileStoreMigratesLegacyProfiles() {
        let legacy = UserDefaults(suiteName: "legacy.\(UUID().uuidString)")!
        let target = UserDefaults(suiteName: "target.\(UUID().uuidString)")!
        ProfileStore(defaults: legacy).save([pi])
        ProfileStore(defaults: legacy).activeProfileID = pi.id
        SharedStorage.migrate(from: legacy, to: target)
        XCTAssertEqual(ProfileStore(defaults: target).load(), [pi])
        XCTAssertEqual(ProfileStore(defaults: target).activeProfileID, pi.id)
        // Nie nadpisuje istniejących danych.
        ProfileStore(defaults: target).save([nas])
        SharedStorage.migrate(from: legacy, to: target)
        XCTAssertEqual(ProfileStore(defaults: target).load(), [nas])
    }
}

private extension WidgetSnapshot {
    var stateTitleForTests: String { protectionEnabled ? "on" : (pausedForMs != nil ? "paused" : "off") }
}
