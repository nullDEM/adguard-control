import XCTest
@testable import AdGuardControl

/// Parsowanie przykładowych odpowiedzi w formacie zgodnym z OpenAPI AdGuard Home.
final class ParsingTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func client(returning json: String) -> AdGuardAPIClient {
        MockURLProtocol.handler = { TestSupport.respond(json: json, for: $0) }
        return TestSupport.client()
    }

    func testParsesServerStatus() async throws {
        let status = try await client(returning: """
        {"dns_addresses":["127.0.0.1","192.168.1.5"],"dns_port":53,"http_port":3000,"protection_enabled":false,
         "protection_disabled_duration":59000,"dhcp_available":true,"running":true,"version":"v0.107.50","language":"pl",
         "start_time":1700000000000}
        """).status()
        XCTAssertEqual(status.dnsAddresses, ["127.0.0.1", "192.168.1.5"])
        XCTAssertEqual(status.httpPort, 3000)
        XCTAssertFalse(status.protectionEnabled)
        XCTAssertEqual(status.protectionDisabledDuration, 59000)
        XCTAssertEqual(status.version, "v0.107.50")
        XCTAssertEqual(status.language, "pl")
    }

    func testParsesStatsAndKeepsDomainKeysUntouched() async throws {
        let stats = try await client(returning: """
        {"time_units":"hours","num_dns_queries":1000,"num_blocked_filtering":150,"num_replaced_safebrowsing":10,
         "num_replaced_safesearch":2,"num_replaced_parental":40,"avg_processing_time":0.012,
         "top_queried_domains":[{"my_host.example.com":120},{"google.com":80}],
         "top_clients":[{"192.168.1.5":500},{"100.64.0.9":300}],
         "top_blocked_domains":[{"ads_tracker.net":60}],
         "dns_queries":[1,2,3],"blocked_filtering":[0,1,1],"replaced_safebrowsing":[0,0,0],"replaced_parental":[0,0,1]}
        """).stats()
        XCTAssertEqual(stats.totalQueries, 1000)
        XCTAssertEqual(stats.totalBlocked, 200)
        XCTAssertEqual(stats.blockedPercent, 20, accuracy: 0.001)
        XCTAssertEqual(stats.activeClients, 2)
        let domains = TopEntry.entries(stats.topQueriedDomains)
        XCTAssertEqual(domains.map(\.name), ["my_host.example.com", "google.com"], "Klucze z podkreślnikami muszą pozostać bez zmian")
        XCTAssertEqual(domains.first?.value, 120)
        XCTAssertEqual(TopEntry.entries(stats.topBlockedDomains).first?.name, "ads_tracker.net")
        XCTAssertEqual(stats.dnsQueries, [1, 2, 3])
    }

    func testEmptyStatsDoNotDivideByZero() async throws {
        let stats = try await client(returning: "{}").stats()
        XCTAssertEqual(stats.blockedPercent, 0)
        XCTAssertEqual(stats.activeClients, 0)
    }

    func testStatsRequestSendsRecentParameter() async throws {
        _ = try await client(returning: "{}").stats(recentMs: 3_600_000)
        XCTAssertEqual(URLComponents(url: MockURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "3600000")
    }

    func testParsesQueryLog() async throws {
        let log = try await client(returning: """
        {"oldest":"2026-10-20T10:00:00Z","data":[
          {"answer":[{"type":"A","value":"1.2.3.4","ttl":60}],"cached":false,"upstream":"tls://1.1.1.1","client":"192.168.1.5",
           "client_info":{"name":"Telefon","disallowed":false,"disallowed_rule":"","whois":{"country":"PL"}},
           "elapsedMs":"12.5","question":{"class":"IN","name":"example.org","type":"A"},"reason":"NotFilteredNotFound",
           "rules":[],"status":"NOERROR","time":"2026-10-20T10:01:02.123456+02:00"},
          {"client":"192.168.1.6","question":{"class":"IN","name":"ads.example.com","type":"AAAA"},"reason":"FilteredBlackList",
           "rules":[{"filter_list_id":1,"text":"||ads.example.com^"}],"status":"NOERROR","time":"2026-10-20T10:00:00Z"}
        ]}
        """).queryLog(QueryLogParams())
        let items = try XCTUnwrap(log.data)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].domain, "example.org")
        XCTAssertEqual(items[0].clientDisplayName, "Telefon")
        XCTAssertEqual(items[0].elapsedMs, "12.5")
        XCTAssertEqual(items[0].kind, .allowed)
        XCTAssertEqual(items[1].kind, .blocked)
        XCTAssertTrue(items[1].kind.isBlocked)
        XCTAssertEqual(items[1].rules?.first?.text, "||ads.example.com^")
        XCTAssertNotNil(Formatting.parseDate(items[0].time), "Data z ułamkami sekund musi się sparsować")
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    func testQueryKindMapping() {
        XCTAssertEqual(QueryKind(reason: "FilteredSafeBrowsing"), .safeBrowsing)
        XCTAssertEqual(QueryKind(reason: "FilteredParental"), .parental)
        XCTAssertEqual(QueryKind(reason: "NotFilteredWhiteList"), .whitelisted)
        XCTAssertEqual(QueryKind(reason: "Rewrite"), .rewritten)
        XCTAssertEqual(QueryKind(reason: "FilteredSafeSearch"), .safeSearch)
        XCTAssertEqual(QueryKind(reason: nil), .allowed)
    }

    func testParsesFilteringStatusWithNullLists() async throws {
        let status = try await client(returning: """
        {"enabled":true,"interval":24,"filters":[{"id":1,"enabled":true,"name":"AdGuard DNS","url":"https://x/f.txt",
          "rules_count":5912,"last_updated":"2026-10-19T12:18:57+03:00"}],"whitelist_filters":null,
         "user_rules":["||a.com^","@@||b.com^"]}
        """).filteringStatus()
        XCTAssertEqual(status.enabled, true)
        XCTAssertEqual(status.interval, 24)
        XCTAssertEqual(status.filters?.first?.rulesCount, 5912)
        XCTAssertEqual(status.filters?.first?.name, "AdGuard DNS")
        XCTAssertNil(status.whitelistFilters)
        XCTAssertEqual(status.userRules, ["||a.com^", "@@||b.com^"])
    }

    func testParsesClientsAndTags() async throws {
        let clients = try await client(returning: """
        {"clients":[{"name":"Laptop","ids":["192.168.1.7","aa:bb:cc:dd:ee:ff"],"use_global_settings":false,"filtering_enabled":true,
           "parental_enabled":false,"safebrowsing_enabled":true,"safe_search":{"enabled":true,"google":true},
           "use_global_blocked_services":true,"blocked_services":[],"upstreams":["1.1.1.1"],"tags":["device_laptop"],
           "ignore_querylog":false,"ignore_statistics":true,"upstreams_cache_enabled":true,"upstreams_cache_size":4096}],
         "auto_clients":[{"ip":"192.168.1.9","name":"tv","source":"ARP","whois_info":{"country":"PL"}}],
         "supported_tags":["device_laptop","os_ios"]}
        """).clients()
        let laptop = try XCTUnwrap(clients.clients?.first)
        XCTAssertEqual(laptop.ids?.count, 2)
        XCTAssertEqual(laptop.useGlobalSettings, false)
        XCTAssertEqual(laptop.safeSearch?.google, true)
        XCTAssertEqual(laptop.tags, ["device_laptop"])
        XCTAssertEqual(laptop.ignoreStatistics, true)
        XCTAssertEqual(laptop.upstreamsCacheSize, 4096)
        XCTAssertEqual(clients.autoClients?.first?.source, "ARP")
        XCTAssertEqual(clients.supportedTags, ["device_laptop", "os_ios"])
    }

    func testParsesDNSInfo() async throws {
        let info = try await client(returning: """
        {"upstream_dns":["tls://1.1.1.1"],"bootstrap_dns":["9.9.9.10"],"fallback_dns":[],"protection_enabled":true,
         "blocking_mode":"custom_ip","blocking_ipv4":"1.2.3.4","cache_enabled":true,"cache_size":4194304,"cache_ttl_min":0,
         "upstream_mode":"parallel","edns_cs_enabled":true,"dnssec_enabled":false,"use_private_ptr_resolvers":true,
         "local_ptr_upstreams":["192.168.1.1"],"ratelimit":20,"ratelimit_subnet_len_ipv4":24,"upstream_timeout":10,
         "default_local_ptr_upstreams":["10.0.0.10"]}
        """).dnsInfo()
        XCTAssertEqual(info.config.upstreamDns, ["tls://1.1.1.1"])
        XCTAssertEqual(info.config.blockingMode, "custom_ip")
        XCTAssertEqual(info.config.upstreamMode, "parallel")
        XCTAssertEqual(info.config.cacheSize, 4_194_304)
        XCTAssertEqual(info.config.ednsCsEnabled, true)
        XCTAssertEqual(info.config.ratelimitSubnetLenIpv4, 24)
        XCTAssertEqual(info.config.localPtrUpstreams, ["192.168.1.1"])
        XCTAssertEqual(info.defaultLocalPtrUpstreams, ["10.0.0.10"])
    }

    func testParsesUpstreamTestResults() async throws {
        let result = try await client(returning: #"{"1.1.1.1":"OK","tls://bad_host":"upstream failed: i/o timeout"}"#)
            .testUpstreams(UpstreamsConfig(bootstrapDns: [], upstreamDns: ["1.1.1.1"]))
        XCTAssertEqual(result["1.1.1.1"], "OK")
        XCTAssertEqual(result["tls://bad_host"], "upstream failed: i/o timeout", "Klucze nie mogą być zmieniane na camelCase")
    }

    func testParsesDHCPStatusAndInterfaces() async throws {
        let status = try await client(returning: """
        {"enabled":true,"interface_name":"eth0","v4":{"gateway_ip":"192.168.1.1","subnet_mask":"255.255.255.0",
          "range_start":"192.168.1.100","range_end":"192.168.1.200","lease_duration":86400},"v6":{"range_start":"","lease_duration":0},
         "leases":[{"mac":"00:11:09:b3:b3:b8","ip":"192.168.1.101","hostname":"dell","expires":"2026-10-21T10:00:00Z"}],
         "static_leases":[{"mac":"aa:bb:cc:dd:ee:ff","ip":"192.168.1.50","hostname":"nas"}]}
        """).dhcpStatus()
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.interfaceName, "eth0")
        XCTAssertEqual(status.v4?.rangeEnd, "192.168.1.200")
        XCTAssertEqual(status.v4?.leaseDuration, 86400)
        XCTAssertEqual(status.leases?.first?.hostname, "dell")
        XCTAssertEqual(status.staticLeases?.first?.ip, "192.168.1.50")

        let interfaces = try await client(returning: """
        {"br_lan":{"name":"br_lan","gateway_ip":"192.168.1.1","hardware_address":"52:54:00:11:09:ba",
          "ipv4_addresses":["192.168.1.2"],"ipv6_addresses":[],"flags":"up|broadcast"}}
        """).dhcpInterfaces()
        XCTAssertEqual(interfaces["br_lan"]?.gatewayIp, "192.168.1.1")
        XCTAssertEqual(interfaces["br_lan"]?.ipv4Addresses, ["192.168.1.2"])
    }

    func testParsesTLSStatus() async throws {
        let tls = try await client(returning: """
        {"enabled":true,"server_name":"example.org","force_https":false,"port_https":443,"port_dns_over_tls":853,
         "port_dns_over_quic":784,"valid_cert":true,"valid_chain":false,"subject":"CN=example.org","issuer":"CN=Test CA",
         "not_after":"2027-01-01T00:00:00Z","dns_names":["example.org"],"valid_key":true,"key_type":"ECDSA","valid_pair":true,
         "warning_validation":"certificate is self-signed","private_key_saved":true}
        """).tlsStatus()
        XCTAssertEqual(tls.serverName, "example.org")
        XCTAssertEqual(tls.portDnsOverTls, 853)
        XCTAssertEqual(tls.validChain, false)
        XCTAssertEqual(tls.warningValidation, "certificate is self-signed")
        XCTAssertEqual(tls.privateKeySaved, true)
    }

    func testParsesAccessListAndClientSearch() async throws {
        let access = try await client(returning: #"{"allowed_clients":["192.168.1.0/24"],"disallowed_clients":["10.0.0.7"],"blocked_hosts":["version.bind"]}"#)
            .accessList()
        XCTAssertEqual(access.allowed, ["192.168.1.0/24"])
        XCTAssertEqual(access.disallowed, ["10.0.0.7"])
        XCTAssertEqual(access.blocked, ["version.bind"])

        let found = try await client(returning: #"[{"cli_42":{"name":"Client 42","ids":["cli_42"],"disallowed":true,"disallowed_rule":"10.0.0.7"}}]"#)
            .searchClients(ids: ["cli_42"])
        XCTAssertEqual(found.first?["cli_42"]?.name, "Client 42")
        XCTAssertEqual(found.first?["cli_42"]?.disallowed, true)
    }

    func testParsesConfigsAndBlockedServices() async throws {
        let stats = try await client(returning: #"{"enabled":true,"interval":86400000,"ignored":["a.com"],"ignored_enabled":true}"#).statsConfig()
        XCTAssertEqual(stats.days, 1)
        XCTAssertEqual(stats.ignored, ["a.com"])

        let log = try await client(returning: #"{"enabled":true,"interval":604800000,"anonymize_client_ip":true,"ignored":[]}"#).queryLogConfig()
        XCTAssertEqual(log.days, 7)
        XCTAssertTrue(log.anonymizeClientIp)

        let all = try await client(returning: #"{"blocked_services":[{"id":"youtube","name":"YouTube","icon_svg":"PHN2Zz4=","rules":["||youtube.com^"],"group_id":"video"}],"groups":[{"id":"video"}]}"#)
            .allBlockedServices()
        XCTAssertEqual(all.blockedServices.first?.name, "YouTube")
        XCTAssertEqual(all.blockedServices.first?.groupId, "video")

        let schedule = try await client(returning: #"{"ids":["youtube"],"schedule":{"time_zone":"Europe/Warsaw","mon":{"start":0,"end":3600000}}}"#)
            .blockedServices()
        XCTAssertEqual(schedule.ids, ["youtube"])
        XCTAssertEqual(schedule.schedule?.timeZone, "Europe/Warsaw")
        XCTAssertEqual(schedule.schedule?.mon?.end, 3_600_000)
    }

    func testParsesVersionInfoAndProfile() async throws {
        let version = try await client(returning: #"{"disabled":false,"new_version":"v0.108","announcement":"Nowa wersja","can_autoupdate":true}"#)
            .versionInfo(recheck: true)
        XCTAssertEqual(version.newVersion, "v0.108")
        XCTAssertEqual(version.canAutoupdate, true)
        XCTAssertEqual(TestSupport.jsonBody()?["recheck_now"] as? Bool, true)

        let profile = try await client(returning: #"{"name":"admin","language":"pl","theme":"dark"}"#).profile()
        XCTAssertEqual(profile, ProfileInfo(name: "admin", language: "pl", theme: "dark"))
    }

    func testParsesFilterCheckHost() async throws {
        let result = try await client(returning: #"{"reason":"FilteredBlackList","rules":[{"filter_list_id":1,"text":"||example.org^"}]}"#)
            .checkHost(name: "example.org", client: "192.168.1.5")
        XCTAssertEqual(QueryKind(reason: result.reason), .blocked)
        XCTAssertEqual(result.rules?.first?.text, "||example.org^")
        let items = URLComponents(url: MockURLProtocol.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "example.org")
        XCTAssertEqual(items.first { $0.name == "client" }?.value, "192.168.1.5")
    }
}
