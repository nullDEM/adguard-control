import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Lokalna walidacja pól formularzy (komunikaty pokazywane przy polach, zanim cokolwiek trafi na serwer).
enum Validators {
    static func isIPv4(_ text: String) -> Bool {
        var address = in_addr()
        return text.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    static func isIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        return text.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    static func isIPAddress(_ text: String) -> Bool { isIPv4(text) || isIPv6(text) }

    /// Adres MAC: 6 par szesnastkowych rozdzielonych `:` lub `-`.
    static func isMAC(_ text: String) -> Bool {
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "-" })
        return parts.count == 6 && parts.allSatisfy { part in part.count == 2 && part.allSatisfy { $0.isHexDigit } }
    }

    /// Nazwa domeny / hosta (z opcjonalnym `*.` na początku).
    static func isDomain(_ text: String) -> Bool {
        var name = text
        if name.hasPrefix("*.") { name.removeFirst(2) }
        guard !name.isEmpty, name.count <= 253, !name.hasPrefix("."), !name.hasSuffix("."), !name.contains("..") else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }
    }

    // MARK: Komunikaty (nil = poprawnie lub pole jeszcze puste)

    static func filterURLError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") { return nil }   // ścieżka pliku na serwerze
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return "Podaj adres http(s):// albo bezwzględną ścieżkę pliku na serwerze."
        }
        return nil
    }

    static func rewriteDomainError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return isDomain(text) ? nil : "Nieprawidłowa domena (litery, cyfry, „-”, „.”; opcjonalnie *. na początku)."
    }

    /// Odpowiedź przepisania: adres IP, nazwa CNAME albo słowa kluczowe `A` / `AAAA`.
    static func rewriteAnswerError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if isIPAddress(text) || text == "A" || text == "AAAA" { return nil }
        if text.allSatisfy({ $0.isNumber || $0 == "." }) { return "Nieprawidłowy adres IP." }
        return isDomain(text) ? nil : "Podaj adres IP albo nazwę domeny (CNAME)."
    }

    static func macError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return isMAC(text) ? nil : "Adres MAC powinien mieć format aa:bb:cc:dd:ee:ff."
    }

    static func ipError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return isIPAddress(text) ? nil : "Nieprawidłowy adres IP."
    }

    /// Identyfikator klienta: IP, CIDR (`192.168.1.0/24`), adres MAC albo ClientID (litery, cyfry, `-`).
    static func isClientID(_ text: String) -> Bool {
        if isIPAddress(text) || isMAC(text) { return true }
        if let slash = text.firstIndex(of: "/") {
            let ip = String(text[..<slash]), prefix = Int(text[text.index(after: slash)...])
            guard let prefix else { return false }
            return (isIPv4(ip) && (0...32).contains(prefix)) || (isIPv6(ip) && (0...128).contains(prefix))
        }
        return text.count <= 63 && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Pierwszy niepoprawny identyfikator z listy (po jednym w linii) – `nil`, gdy wszystkie są poprawne.
    static func clientIDsError(_ lines: [String]) -> String? {
        guard let bad = lines.first(where: { !isClientID($0) }) else { return nil }
        return "„\(bad)” nie jest poprawnym identyfikatorem (IP, CIDR, MAC lub ClientID)."
    }

    static func hostnameError(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return isDomain(text) && !text.contains("*") ? nil : "Nazwa hosta nie może zawierać spacji ani znaków specjalnych."
    }
}

/// Wiersz błędu pod polem formularza.
import SwiftUI

struct FieldError: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Błąd: \(message)")
        }
    }
}
