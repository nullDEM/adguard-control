import Foundation

/// Normalizacja adresu serwera wpisanego przez użytkownika.
///
/// - brak schematu → `http://`
/// - dozwolone tylko `http` i `https`
/// - usuwane: końcowe `/`, końcówka `/control`, query, fragment, dane logowania
/// - adres przechodzi przez `AddressPolicy` (zakazane adresy specjalne, HTTP tylko w sieci prywatnej / tailnecie)
enum URLNormalizer {
    static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw APIError.invalidURL }
        if !text.contains("://") { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { throw APIError.invalidURL }

        if let port = components.port, !(1...65535).contains(port) { throw APIError.invalidURL }

        components.scheme = scheme
        // Adresów IPv6 nie przepisujemy – `URLComponents` bywa kapryśny przy nawiasach.
        if !host.contains(":") { components.host = host.lowercased() }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/control") { path.removeLast("/control".count) }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path

        guard let url = components.url else { throw APIError.invalidURL }
        try AddressPolicy.validate(url)
        return url
    }

    /// Wersja tekstowa (bez końcowego `/`) – to zapisujemy w profilu.
    static func normalizedString(_ input: String) throws -> String {
        try normalize(input).absoluteString
    }
}

/// Rodzaj sieci, w której znajduje się host serwera.
enum HostClass: Equatable {
    case tailnet          // 100.64.0.0/10, fd7a:115c:a1e0::/48, *.ts.net
    case privateNetwork   // RFC 1918, ULA, link-local IPv6, *.local, krótkie nazwy
    case loopback
    case publicInternet
    case forbidden        // adresy specjalne, na które nie wolno wysyłać poświadczeń
}

/// Polityka adresów serwera. Chroni przed wysłaniem loginu i hasła (HTTP Basic) otwartym tekstem
/// przez internet oraz przed adresami specjalnymi (np. metadane chmury 169.254.x.x).
enum AddressPolicy {
    private static let localSuffixes = [".local", ".lan", ".home", ".internal", ".home.arpa", ".localdomain", ".intranet"]

    static func classify(host rawHost: String) -> HostClass {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.isEmpty { return .forbidden }

        if host.contains(":") { return classifyIPv6(host) }
        if let octets = ipv4Octets(host) { return classifyIPv4(octets) }

        if host == "localhost" || host.hasSuffix(".localhost") { return .loopback }
        if host.hasSuffix(".ts.net") { return .tailnet }
        if !host.contains(".") { return .privateNetwork }          // krótka nazwa (MagicDNS / mDNS)
        if localSuffixes.contains(where: { host.hasSuffix($0) }) { return .privateNetwork }
        return .publicInternet
    }

    /// Rzuca `APIError`, gdy adres nie nadaje się do wysyłania poświadczeń.
    static func validate(_ url: URL) throws {
        guard let host = url.host, !host.isEmpty else { throw APIError.invalidURL }
        switch classify(host: host) {
        case .forbidden:
            throw APIError.forbiddenAddress
        case .publicInternet where url.scheme?.lowercased() != "https":
            throw APIError.insecureTransport
        default:
            return
        }
    }

    // MARK: IPv4 / IPv6

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    private static func classifyIPv4(_ o: [Int]) -> HostClass {
        switch (o[0], o[1]) {
        case (0, _), (255, _): return .forbidden                  // 0.0.0.0/8, broadcast
        case (224...239, _): return .forbidden                    // multicast
        case (169, 254): return .forbidden                        // link-local, metadane chmury
        case (127, _): return .loopback
        case (10, _), (192, 168): return .privateNetwork
        case (172, 16...31): return .privateNetwork
        case (100, 64...127): return .tailnet
        default: return .publicInternet
        }
    }

    private static func classifyIPv6(_ host: String) -> HostClass {
        if host == "::" { return .forbidden }
        if host == "::1" { return .loopback }
        if host.hasPrefix("fd7a:115c:a1e0:") { return .tailnet }
        if host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb") { return .privateNetwork }
        if host.hasPrefix("fc") || host.hasPrefix("fd") { return .privateNetwork }
        if host.hasPrefix("ff") { return .forbidden }
        return .publicInternet
    }
}

/// Walidacja pól formularza profilu – komunikaty wyświetlane przy polach.
enum ProfileValidator {
    static func nameError(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Podaj nazwę profilu." : nil
    }

    static func addressError(_ address: String) -> String? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }   // puste pole oznaczamy dopiero po próbie zapisu
        do {
            _ = try URLNormalizer.normalize(text)
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "Nieprawidłowy adres serwera."
        }
    }

    /// Login HTTP Basic nie może zawierać dwukropka (RFC 7617) ani znaków sterujących.
    static func usernameError(_ username: String) -> String? {
        if username.contains(":") { return "Login nie może zawierać dwukropka (to ogranicza HTTP Basic)." }
        if username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Login zawiera niedozwolone znaki."
        }
        return nil
    }

    /// Ostrzeżenie (nie błąd): HTTP bez Tailscale w sieci lokalnej.
    static func transportWarning(address: String, requireTailscale: Bool) -> String? {
        guard let url = try? URLNormalizer.normalize(address), url.scheme == "http", let host = url.host else { return nil }
        switch AddressPolicy.classify(host: host) {
        case .privateNetwork where !requireTailscale:
            return "Połączenie HTTP w sieci lokalnej nie jest szyfrowane. Poza domem użyj Tailscale."
        default:
            return nil
        }
    }
}
