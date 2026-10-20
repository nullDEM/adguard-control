import Foundation

/// Błędy warstwy sieciowej wraz z czytelnymi komunikatami i diagnostyką.
enum APIError: Error, Equatable, LocalizedError {
    case invalidURL
    case insecureTransport
    case forbiddenAddress
    case conflict(String)
    case noConnection
    case timeout
    case hostUnreachable
    case unauthorized
    case forbidden
    case certificate(String)
    case tailscaleRequired
    case notImplemented(String)
    case server(status: Int, message: String)
    case decoding(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Nieprawidłowy adres serwera. Podaj adres w formacie http://host:port."
        case .insecureTransport:
            return "Połączenie przez HTTP z adresem publicznym jest zablokowane – login i hasło poszłyby otwartym tekstem. Użyj HTTPS albo Tailscale."
        case .forbiddenAddress:
            return "Ten adres jest niedozwolony (adres specjalny, np. 0.0.0.0, 169.254.x.x lub multicast)."
        case .conflict(let detail):
            return detail
        case .noConnection:
            return "Brak połączenia z siecią."
        case .timeout:
            return "Serwer nie odpowiedział w wymaganym czasie."
        case .hostUnreachable:
            return "Nie można połączyć się z serwerem AdGuard Home."
        case .unauthorized:
            return "Nieprawidłowy login lub hasło (401)."
        case .forbidden:
            return "Brak uprawnień do wykonania tej operacji (403)."
        case .certificate(let detail):
            return "Problem z certyfikatem HTTPS: \(detail)"
        case .tailscaleRequired:
            return "Włączono „Wymagaj Tailscale”, ale iPhone nie ma aktywnego połączenia z Tailscale."
        case .notImplemented(let message):
            return message.isEmpty ? "Funkcja nie jest dostępna na tym serwerze." : message
        case .server(let status, let message):
            return message.isEmpty ? "Błąd serwera (\(status))." : "Błąd serwera (\(status)): \(message)"
        case .decoding(let detail):
            return "Nieoczekiwana odpowiedź serwera: \(detail)"
        case .cancelled:
            return "Anulowano."
        case .unknown(let detail):
            return detail
        }
    }

    /// Wskazówki diagnostyczne wyświetlane obok błędu.
    var diagnostics: [String] {
        switch self {
        case .noConnection, .timeout, .hostUnreachable, .tailscaleRequired:
            return [
                "Sprawdź, czy iPhone jest połączony z Tailscale",
                "Sprawdź, czy Raspberry Pi jest online w panelu Tailscale",
                "Sprawdź, czy AdGuard Home działa i jaki ma port panelu (często 80 lub 3000)",
                "Sprawdź, czy adres i port są poprawne"
            ]
        case .invalidURL:
            return ["Sprawdź, czy adres i port są poprawne (np. http://100.x.y.z lub http://100.x.y.z:3000)"]
        case .insecureTransport:
            return ["Dla adresów publicznych używaj https://", "Najbezpieczniej: adres Tailscale 100.x.y.z lub MagicDNS"]
        case .conflict:
            return ["Dane zostały odświeżone – sprawdź zmiany i zapisz ponownie"]
        case .unauthorized:
            return ["Sprawdź login i hasło panelu AdGuard Home"]
        case .certificate:
            return ["Użyj adresu zgodnego z certyfikatem lub połącz się przez HTTP wewnątrz tailnetu"]
        default:
            return []
        }
    }

    /// Nagłówek ekranu błędu.
    var title: String {
        switch self {
        case .unauthorized, .forbidden: return "Brak dostępu"
        case .tailscaleRequired: return "Brak połączenia z Tailscale"
        case .insecureTransport, .forbiddenAddress, .invalidURL: return "Nieprawidłowy adres serwera"
        case .certificate: return "Problem z certyfikatem"
        case .decoding, .server, .notImplemented, .conflict: return "Błąd serwera"
        default: return "Błąd połączenia"
        }
    }

    var symbol: String {
        switch self {
        case .unauthorized, .forbidden: return "lock.slash"
        case .tailscaleRequired: return "network.slash"
        case .insecureTransport, .forbiddenAddress, .invalidURL: return "exclamationmark.shield"
        case .certificate: return "lock.trianglebadge.exclamationmark"
        case .decoding, .server, .notImplemented, .conflict: return "server.rack"
        default: return "wifi.exclamationmark"
        }
    }

    var isAuthorizationProblem: Bool { self == .unauthorized || self == .forbidden }

    static func from(urlError error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .noConnection
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .resourceUnavailable:
            return .hostUnreachable
        case .cancelled:
            return .cancelled
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected,
             .clientCertificateRequired:
            return .certificate(error.localizedDescription)
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
