import Foundation

/// Delegat zadania, który odmawia przekierowań: nagłówek `Authorization` nigdy nie trafi pod inny adres.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Krótkotrwały cache odpowiedzi GET (surowe dane JSON). Każda operacja zapisu czyści cały cache.
final class ResponseCache: @unchecked Sendable {
    private struct Entry { let data: Data; let expires: Date }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func data(for key: String, now: Date = Date()) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        if entry.expires <= now { entries[key] = nil; return nil }
        return entry.data
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = Entry(data: data, expires: now.addingTimeInterval(ttl))
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
}

/// Klient REST API AdGuard Home (`/control/...`) z autoryzacją HTTP Basic.
/// Nie loguje nagłówków ani haseł, nie podąża za przekierowaniami i nie zapisuje cookies.
final class AdGuardAPIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let authorization: String
    private let requireTailscale: Bool
    private let tailscaleProbe: TailscaleProbing
    let cache = ResponseCache()

    /// Czasy życia cache dla odczytów statystycznych (sekundy).
    enum TTL {
        static let status: TimeInterval = 3
        static let stats: TimeInterval = 10
        static let config: TimeInterval = 30
        static let catalog: TimeInterval = 3600   // katalog usług (~290 KB) praktycznie się nie zmienia
    }

    /// Dekoder z konwersją snake_case → camelCase.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Dekoder „surowy” – dla odpowiedzi, w których klucze map są danymi (domeny, IP, nazwy interfejsów).
    static let plainDecoder = JSONDecoder()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static func makeSession(timeout: TimeInterval = 15) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    static func basicAuthHeader(username: String, password: String) -> String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    init(baseURL: URL,
         username: String,
         password: String,
         requireTailscale: Bool = false,
         session: URLSession = AdGuardAPIClient.makeSession(),
         tailscaleProbe: TailscaleProbing = SystemTailscaleProbe()) {
        self.baseURL = baseURL
        self.authorization = Self.basicAuthHeader(username: username, password: password)
        self.requireTailscale = requireTailscale
        self.session = session
        self.tailscaleProbe = tailscaleProbe
    }

    // MARK: - Budowanie żądań

    func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = components.path + "/control" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    func makeRequest(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: - Transport

    func invalidateCache() { cache.removeAll() }

    @discardableResult
    func perform(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        if requireTailscale && !tailscaleProbe.isTailscaleActive() { throw APIError.tailscaleRequired }
        try AddressPolicy.validate(baseURL)

        let request = try makeRequest(method: method, path: path, query: query, body: body)
        // Każda zmiana po stronie serwera unieważnia dane z cache.
        if method != "GET" { cache.removeAll() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unknown("Brak odpowiedzi HTTP.") }
        switch http.statusCode {
        case 200..<300: return data
        case 300..<400:
            throw APIError.server(status: http.statusCode,
                                  message: "Serwer przekierował żądanie. Sprawdź, czy adres i schemat (HTTP/HTTPS) są poprawne.")
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 501: throw APIError.notImplemented(Self.message(from: data))
        default: throw APIError.server(status: http.statusCode, message: Self.message(from: data))
        }
    }

    /// Komunikat błędu z ciała odpowiedzi: bez znaczników HTML, w jednej linii, z limitem długości.
    static func message(from data: Data) -> String {
        struct ErrorBody: Decodable { var message: String? }
        let raw: String
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message {
            raw = message
        } else {
            raw = String(decoding: data.prefix(600), as: UTF8.self)
        }
        return sanitize(raw)
    }

    static func sanitize(_ text: String, limit: Int = 160) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<[^>]*>") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        result = result.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return result.count > limit ? String(result.prefix(limit)) + "…" : result
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, plain: Bool) throws -> T {
        do {
            return try (plain ? Self.plainDecoder : Self.decoder).decode(type, from: data)
        } catch {
            throw APIError.decoding(Self.sanitize(String(describing: error), limit: 120))
        }
    }

    private func encode<B: Encodable>(_ body: B) throws -> Data {
        do { return try Self.encoder.encode(body) } catch { throw APIError.unknown("Nie można zakodować żądania.") }
    }

    /// `ttl > 0` → odpowiedź jest buforowana (klucz: ścieżka + parametry).
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], plain: Bool = false,
                           ttl: TimeInterval = 0) async throws -> T {
        let key = path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        if ttl > 0, let cached = cache.data(for: key) {
            return try decode(T.self, from: cached, plain: plain)
        }
        let data = try await perform("GET", path, query: query)
        let value = try decode(T.self, from: data, plain: plain)
        if ttl > 0 { cache.store(data, for: key, ttl: ttl) }
        return value
    }

    func send<B: Encodable>(_ method: String, _ path: String, body: B) async throws {
        try await perform(method, path, body: try encode(body))
    }

    func send<B: Encodable, T: Decodable>(_ method: String, _ path: String, body: B, plain: Bool = false) async throws -> T {
        try decode(T.self, from: try await perform(method, path, body: try encode(body)), plain: plain)
    }

    func send(_ method: String, _ path: String) async throws {
        try await perform(method, path)
    }

    // MARK: - Status i ochrona (global)

    func status() async throws -> ServerStatus { try await get("/status", ttl: TTL.status) }
    func setProtection(enabled: Bool, durationMs: UInt64? = nil) async throws {
        try await send("POST", "/protection", body: SetProtectionRequest(enabled: enabled, duration: enabled ? nil : durationMs))
    }
    func dnsInfo() async throws -> DNSInfo { try await get("/dns_info") }
    func setDNSConfig(_ config: DNSConfig) async throws { try await send("POST", "/dns_config", body: config) }
    func clearCache() async throws { try await send("POST", "/cache_clear") }
    func testUpstreams(_ config: UpstreamsConfig) async throws -> UpstreamsConfigResponse {
        try await send("POST", "/test_upstream_dns", body: config, plain: true)
    }
    func versionInfo(recheck: Bool) async throws -> VersionInfo {
        try await send("POST", "/version.json", body: GetVersionRequest(recheckNow: recheck))
    }
    func beginUpdate() async throws { try await send("POST", "/update") }
    func profile() async throws -> ProfileInfo { try await get("/profile") }
    func updateProfile(_ profile: ProfileInfo) async throws { try await send("PUT", "/profile/update", body: profile) }

    // MARK: - Query log

    func queryLog(_ params: QueryLogParams) async throws -> QueryLog {
        try await get("/querylog", query: params.queryItems)
    }
    func queryLogConfig() async throws -> QueryLogConfig { try await get("/querylog/config", ttl: TTL.config) }
    func setQueryLogConfig(_ config: QueryLogConfig) async throws { try await send("PUT", "/querylog/config/update", body: config) }
    func clearQueryLog() async throws { try await send("POST", "/querylog_clear") }

    // MARK: - Statystyki

    func stats(recentMs: Int? = nil) async throws -> Stats {
        let query = recentMs.map { [URLQueryItem(name: "recent", value: String($0))] } ?? []
        return try await get("/stats", query: query, plain: true, ttl: TTL.stats)
    }
    func statsConfig() async throws -> StatsConfig { try await get("/stats/config", ttl: TTL.config) }
    func setStatsConfig(_ config: StatsConfig) async throws { try await send("PUT", "/stats/config/update", body: config) }
    func resetStats() async throws { try await send("POST", "/stats_reset") }

    // MARK: - TLS

    func tlsStatus() async throws -> TlsConfig { try await get("/tls/status") }
    func tlsConfigure(_ config: TlsConfig) async throws -> TlsConfig { try await send("POST", "/tls/configure", body: config) }
    func tlsValidate(_ config: TlsConfig) async throws -> TlsConfig { try await send("POST", "/tls/validate", body: config) }

    // MARK: - DHCP

    func dhcpStatus() async throws -> DhcpStatus { try await get("/dhcp/status") }
    func dhcpInterfaces() async throws -> DHCPNetInterfaces { try await get("/dhcp/interfaces", plain: true) }
    func dhcpSetConfig(_ config: DhcpConfig) async throws { try await send("POST", "/dhcp/set_config", body: config) }
    func dhcpFindActive(interface: String) async throws -> DhcpSearchResult {
        try await send("POST", "/dhcp/find_active_dhcp", body: DhcpFindActiveReq(interface: interface))
    }
    func dhcpAddStaticLease(_ lease: DhcpStaticLease) async throws { try await send("POST", "/dhcp/add_static_lease", body: lease) }
    func dhcpRemoveStaticLease(_ lease: DhcpStaticLease) async throws { try await send("POST", "/dhcp/remove_static_lease", body: lease) }
    func dhcpUpdateStaticLease(_ lease: DhcpStaticLease) async throws { try await send("POST", "/dhcp/update_static_lease", body: lease) }
    func dhcpReset() async throws { try await send("POST", "/dhcp/reset") }
    func dhcpResetLeases() async throws { try await send("POST", "/dhcp/reset_leases") }

    // MARK: - Filtrowanie

    func filteringStatus() async throws -> FilterStatus { try await get("/filtering/status") }
    func setFilteringConfig(_ config: FilterConfig) async throws { try await send("POST", "/filtering/config", body: config) }
    func addFilter(name: String, url: String, whitelist: Bool) async throws {
        try await send("POST", "/filtering/add_url", body: AddUrlRequest(name: name, url: url, whitelist: whitelist))
    }
    func removeFilter(url: String, whitelist: Bool) async throws {
        try await send("POST", "/filtering/remove_url", body: RemoveUrlRequest(url: url, whitelist: whitelist))
    }
    func updateFilter(url: String, name: String, newURL: String, enabled: Bool, whitelist: Bool) async throws {
        let body = FilterSetUrl(data: FilterSetUrlData(enabled: enabled, name: name, url: newURL), url: url, whitelist: whitelist)
        try await send("POST", "/filtering/set_url", body: body)
    }
    @discardableResult
    func refreshFilters(whitelist: Bool) async throws -> Int {
        let response: FilterRefreshResponse = try await send("POST", "/filtering/refresh", body: FilterRefreshRequest(whitelist: whitelist))
        return response.updated ?? 0
    }
    func setUserRules(_ rules: [String]) async throws { try await send("POST", "/filtering/set_rules", body: SetRulesRequest(rules: rules)) }
    func checkHost(name: String, client: String? = nil, qtype: String? = nil) async throws -> FilterCheckHostResponse {
        var query = [URLQueryItem(name: "name", value: name)]
        if let client, !client.isEmpty { query.append(.init(name: "client", value: client)) }
        if let qtype, !qtype.isEmpty { query.append(.init(name: "qtype", value: qtype)) }
        return try await get("/filtering/check_host", query: query)
    }

    // MARK: - Safe browsing / parental / safe search

    func safeBrowsingStatus() async throws -> EnabledStatus { try await get("/safebrowsing/status") }
    func setSafeBrowsing(_ enabled: Bool) async throws { try await send("POST", enabled ? "/safebrowsing/enable" : "/safebrowsing/disable") }
    func parentalStatus() async throws -> ParentalStatus { try await get("/parental/status") }
    func setParental(_ enabled: Bool) async throws { try await send("POST", enabled ? "/parental/enable" : "/parental/disable") }
    func safeSearchStatus() async throws -> SafeSearchConfig { try await get("/safesearch/status") }
    func setSafeSearch(_ config: SafeSearchConfig) async throws { try await send("PUT", "/safesearch/settings", body: config) }

    // MARK: - Klienci i kontrola dostępu

    func clients() async throws -> Clients { try await get("/clients") }
    func addClient(_ client: Client) async throws { try await send("POST", "/clients/add", body: client) }
    func updateClient(name: String, data: Client) async throws {
        try await send("POST", "/clients/update", body: ClientUpdate(name: name, data: data))
    }
    func deleteClient(name: String) async throws { try await send("POST", "/clients/delete", body: ClientDelete(name: name)) }
    func searchClients(ids: [String]) async throws -> ClientsFindResponse {
        try await send("POST", "/clients/search", body: ClientsSearchRequest(clients: ids.map { ClientsSearchRequestItem(id: $0) }), plain: true)
    }
    func accessList() async throws -> AccessList { try await get("/access/list") }
    func setAccessList(_ list: AccessList) async throws { try await send("POST", "/access/set", body: list) }

    // MARK: - Zablokowane usługi

    func allBlockedServices() async throws -> BlockedServicesAll { try await get("/blocked_services/all", ttl: TTL.catalog) }
    func blockedServices() async throws -> BlockedServicesSchedule { try await get("/blocked_services/get") }
    func setBlockedServices(_ value: BlockedServicesSchedule) async throws { try await send("PUT", "/blocked_services/update", body: value) }

    // MARK: - DNS rewrites

    func rewrites() async throws -> [RewriteEntry] { try await get("/rewrite/list") }
    func addRewrite(_ entry: RewriteEntry) async throws { try await send("POST", "/rewrite/add", body: entry) }
    func deleteRewrite(_ entry: RewriteEntry) async throws { try await send("POST", "/rewrite/delete", body: entry) }
    func updateRewrite(target: RewriteEntry, update: RewriteEntry) async throws {
        try await send("PUT", "/rewrite/update", body: RewriteUpdate(target: target, update: update))
    }
    func rewriteSettings() async throws -> RewriteSettings { try await get("/rewrite/settings") }
    func setRewriteSettings(_ settings: RewriteSettings) async throws { try await send("PUT", "/rewrite/settings/update", body: settings) }

    // MARK: - Operacje „odczytaj → zmień → zapisz” (nie nadpisują zmian wykonanych gdzie indziej)

    /// Zmienia tylko podane pola konfiguracji filtrowania; zwraca poprzednią konfigurację (do cofnięcia).
    @discardableResult
    func updateFilteringConfig(enabled: Bool? = nil, interval: Int? = nil) async throws -> FilterConfig {
        let current = try await filteringStatus()
        let previous = FilterConfig(enabled: current.enabled, interval: current.interval)
        try await setFilteringConfig(FilterConfig(enabled: enabled ?? current.enabled, interval: interval ?? current.interval))
        return previous
    }

    /// Pobiera aktualne reguły użytkownika, przekształca je i zapisuje. `transform` zwraca `nil`, gdy nic nie trzeba zmieniać.
    /// Zwraca reguły sprzed zmiany.
    @discardableResult
    func modifyUserRules(_ transform: ([String]) -> [String]?) async throws -> [String] {
        let current = try await filteringStatus().userRules ?? []
        if let updated = transform(current), updated != current { try await setUserRules(updated) }
        return current
    }

    /// Pobiera aktualną listę dostępu, zmienia ją i zapisuje; zwraca listę sprzed zmiany.
    @discardableResult
    func modifyAccessList(_ transform: (inout AccessList) -> Void) async throws -> AccessList {
        let current = try await accessList()
        var updated = current
        transform(&updated)
        if updated != current { try await setAccessList(updated) }
        return current
    }
}
