#if DEBUG
import Foundation

/// Tryb testów UI (`-uitest`): aplikacja nie łączy się z siecią, tylko z wbudowanym, stanowym serwerem testowym.
/// Dostępny wyłącznie w buildach Debug – nie trafia do wydania.
enum UITestSupport {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") }
    private static var startsEmpty: Bool { ProcessInfo.processInfo.arguments.contains("-uitest-empty") }

    private struct AlwaysOn: TailscaleProbing { func isTailscaleActive() -> Bool { true } }

    @MainActor
    static func makeAppState() -> AppState {
        StubServer.reset()
        let defaults = UserDefaults(suiteName: "uitest.\(UUID().uuidString)") ?? .standard
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: AlwaysOn(), sessionFactory: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubServer.self]
            return URLSession(configuration: configuration)
        })
        if !startsEmpty {
            try? app.save(profile: ServerProfile(name: "Testowy Pi", address: "http://100.64.0.5:3000", username: "admin"),
                          password: "pw")
        }
        return app
    }
}

final class StubServer: URLProtocol {
    private static let lock = NSLock()
    private static var protectionEnabled = true

    static func reset() { lock.lock(); protectionEnabled = true; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let path = url.path.replacingOccurrences(of: "/control", with: "")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
        } else if let data = request.httpBody { body = data }

        Self.lock.lock()
        if path == "/protection", let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let enabled = json["enabled"] as? Bool { Self.protectionEnabled = enabled }
        let enabled = Self.protectionEnabled
        Self.lock.unlock()

        let json = Self.json(for: path, query: query, protection: enabled)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func json(for path: String, query: [URLQueryItem], protection: Bool) -> String {
        switch path {
        case "/status":
            return #"{"dns_addresses":["192.168.1.2"],"dns_port":53,"http_port":3000,"protection_enabled":\#(protection),"protection_disabled_duration":0,"running":true,"version":"v0.107.50","language":"pl","dhcp_available":false}"#
        case "/stats":
            return #"{"time_units":"hours","num_dns_queries":1000,"num_blocked_filtering":200,"num_replaced_safebrowsing":0,"num_replaced_safesearch":0,"num_replaced_parental":0,"avg_processing_time":0.011,"top_queried_domains":[{"example.com":900}],"top_clients":[{"100.64.0.9":1000}],"top_blocked_domains":[{"ads.tracker.net":200}],"dns_queries":[10,20,30],"blocked_filtering":[1,2,3],"replaced_safebrowsing":[0,0,0],"replaced_parental":[0,0,0]}"#
        case "/querylog":
            let search = query.first { $0.name == "search" }?.value?.lowercased() ?? ""
            let names = ["ads.tracker.net", "example.com", "apple.com"].filter { search.isEmpty || $0.contains(search) }
            let items = names.enumerated().map { index, name in
                let blocked = name.hasPrefix("ads")
                return #"{"client":"100.64.0.9","client_info":{"name":"iPhone","disallowed":false,"disallowed_rule":"","whois":{}},"question":{"class":"IN","name":"\#(name)","type":"A"},"reason":"\#(blocked ? "FilteredBlackList" : "NotFilteredNotFound")","rules":[],"status":"NOERROR","time":"2026-10-20T03:0\#(index):00+02:00","elapsedMs":"3.2","upstream":"tls://1.1.1.1","answer":[]}"#
            }
            return #"{"oldest":"","data":[\#(items.joined(separator: ","))]}"#
        case "/filtering/status":
            return #"{"enabled":true,"interval":24,"filters":[],"whitelist_filters":[],"user_rules":[]}"#
        case "/safebrowsing/status", "/parental/status":
            return #"{"enabled":false,"sensitivity":13}"#
        default:
            return "{}"
        }
    }
}
#endif
