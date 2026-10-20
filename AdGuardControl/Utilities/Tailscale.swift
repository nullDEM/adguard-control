import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Sprawdza, czy iPhone ma aktywny interfejs Tailscale.
/// Aplikacja nie instaluje ani nie konfiguruje Tailscale – tylko wykrywa jego obecność.
protocol TailscaleProbing: Sendable {
    func isTailscaleActive() -> Bool
}

enum TailscaleHelper {
    /// Tailscale używa zakresu CGNAT 100.64.0.0/10.
    static func isTailscaleIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    /// Tailscale tworzy interfejs tunelowy `utunN` z adresem 100.64/10. Adresy CGNAT z sieci komórkowych
    /// (interfejsy `pdp_ip*`) nie oznaczają Tailscale, więc sprawdzamy też nazwę interfejsu.
    static func isTailscaleInterface(name: String, ipv4 address: String) -> Bool {
        name.hasPrefix("utun") && isTailscaleIPv4(address)
    }

    /// Czy host wygląda na adres w tailnecie (IP 100.64/10, `*.ts.net` albo krótka nazwa MagicDNS).
    static func looksLikeTailnetHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if isTailscaleIPv4(lower) { return true }
        if lower.hasSuffix(".ts.net") { return true }
        let isIP = lower.contains(":") || lower.split(separator: ".").allSatisfy { Int($0) != nil }
        return !isIP && !lower.contains(".")
    }

    static let setupHint = """
    Adres Raspberry Pi znajdziesz w panelu Tailscale (login.tailscale.com/admin/machines) \
    albo poleceniem `tailscale ip -4` na Raspberry Pi. Możesz użyć adresu 100.x.y.z albo \
    nazwy MagicDNS, np. adguard-home.tailnet-name.ts.net.
    """
}

struct SystemTailscaleProbe: TailscaleProbing {
    func isTailscaleActive() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            let name = String(cString: current.pointee.ifa_name)
            if result == 0, TailscaleHelper.isTailscaleInterface(name: name, ipv4: String(cString: host)) { return true }
        }
        return false
    }
}
