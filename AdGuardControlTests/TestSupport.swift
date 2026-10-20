import Foundation
@testable import AdGuardControl

/// Przechwytuje żądania URLSession i zwraca przygotowane odpowiedzi.
final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _requests: [URLRequest] = []
    private static var _bodies: [Data] = []

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }

    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    static var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return _bodies }

    static func reset() {
        lock.lock()
        _handler = nil
        _requests = []
        _bodies = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
        } else if let data = request.httpBody {
            body = data
        }
        Self.lock.lock()
        Self._requests.append(request)
        Self._bodies.append(body)
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct StubTailscale: TailscaleProbing {
    var active: Bool
    func isTailscaleActive() -> Bool { active }
}

enum TestSupport {
    static let baseURL = URL(string: "http://100.64.0.5:3000")!

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func client(requireTailscale: Bool = false, tailscaleActive: Bool = true,
                       username: String = "admin", password: String = "secret") -> AdGuardAPIClient {
        AdGuardAPIClient(baseURL: baseURL, username: username, password: password,
                         requireTailscale: requireTailscale, session: session(),
                         tailscaleProbe: StubTailscale(active: tailscaleActive))
    }

    static func respond(status: Int = 200, json: String = "", for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (response, Data(json.utf8))
    }

    static func jsonBody(_ index: Int = 0) -> [String: Any]? {
        guard MockURLProtocol.bodies.indices.contains(index) else { return nil }
        return (try? JSONSerialization.jsonObject(with: MockURLProtocol.bodies[index])) as? [String: Any]
    }
}

extension TestSupport {
    /// `AppState` z jednym profilem (adres w tailnecie) i sesją opartą o `MockURLProtocol`.
    @MainActor
    static func makeApp(address: String = "http://100.64.0.5:3000") throws -> AppState {
        MockURLProtocol.reset()
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let app = AppState(profileStore: ProfileStore(defaults: defaults), passwords: InMemoryPasswordStore(),
                           tailscaleProbe: StubTailscale(active: true), sessionFactory: { TestSupport.session() })
        try app.save(profile: ServerProfile(name: "Pi", address: address, username: "admin"), password: "pw")
        return app
    }

    static func count(path: String) -> Int {
        MockURLProtocol.requests.filter { $0.url?.path == path }.count
    }

    /// Indeks ostatniego żądania na daną ścieżkę (do odczytu treści JSON przez `jsonBody`).
    static func lastIndex(path: String) -> Int? {
        MockURLProtocol.requests.lastIndex { $0.url?.path == path }
    }
}
