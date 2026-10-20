import Foundation

struct DNSConfig: Codable, Equatable {
    var bootstrapDns: [String]?
    var upstreamDns: [String]?
    var fallbackDns: [String]?
    var upstreamDnsFile: String?
    var protectionEnabled: Bool?
    var ratelimit: Int?
    var ratelimitSubnetLenIpv4: Int?
    var ratelimitSubnetLenIpv6: Int?
    var ratelimitWhitelist: [String]?
    var blockingMode: String?
    var blockingIpv4: String?
    var blockingIpv6: String?
    var blockedResponseTtl: Int?
    var protectionDisabledUntil: String?
    var ednsCsEnabled: Bool?
    var ednsCsUseCustom: Bool?
    var ednsCsCustomIp: String?
    var disableIpv6: Bool?
    var dnssecEnabled: Bool?
    var cacheSize: Int?
    var cacheTtlMin: Int?
    var cacheTtlMax: Int?
    var cacheEnabled: Bool?
    var cacheOptimistic: Bool?
    var upstreamMode: String?
    var usePrivatePtrResolvers: Bool?
    var resolveClients: Bool?
    var localPtrUpstreams: [String]?
    var upstreamTimeout: Int?

    static let blockingModes = ["default", "refused", "nxdomain", "null_ip", "custom_ip"]
    static let upstreamModes: [(value: String, title: String)] = [
        ("load_balance", "Równoważenie obciążenia"),
        ("parallel", "Zapytania równoległe"),
        ("fastest_addr", "Najszybszy adres IP")
    ]
}

/// `/dns_info` = `DNSConfig` + `default_local_ptr_upstreams`.
struct DNSInfo: Decodable, Equatable {
    var config: DNSConfig
    var defaultLocalPtrUpstreams: [String]

    private enum ExtraKeys: String, CodingKey { case defaultLocalPtrUpstreams }

    init(from decoder: Decoder) throws {
        config = try DNSConfig(from: decoder)
        let container = try decoder.container(keyedBy: ExtraKeys.self)
        defaultLocalPtrUpstreams = try container.decodeIfPresent([String].self, forKey: .defaultLocalPtrUpstreams) ?? []
    }
}

struct UpstreamsConfig: Codable, Equatable {
    var bootstrapDns: [String]
    var upstreamDns: [String]
    var fallbackDns: [String]?
    var privateUpstream: [String]?
}

typealias UpstreamsConfigResponse = [String: String]

// MARK: - DHCP

struct DhcpConfigV4: Codable, Equatable {
    var gatewayIp: String
    var subnetMask: String
    var rangeStart: String
    var rangeEnd: String
    var leaseDuration: Int
}

struct DhcpConfigV6: Codable, Equatable {
    var rangeStart: String?
    var leaseDuration: Int?
}

struct DhcpLease: Codable, Equatable, Identifiable {
    var mac: String
    var ip: String
    var hostname: String
    var expires: String?
    var id: String { mac + ip }
}

struct DhcpStaticLease: Codable, Equatable, Identifiable {
    var mac: String
    var ip: String
    var hostname: String
    var id: String { mac }
}

struct DhcpStatus: Codable, Equatable {
    var enabled: Bool
    var interfaceName: String
    var v4: DhcpConfigV4?
    var v6: DhcpConfigV6?
    var leases: [DhcpLease]?
    var staticLeases: [DhcpStaticLease]?
}

struct DhcpConfig: Codable, Equatable {
    var enabled: Bool
    var interfaceName: String
    var v4: DhcpConfigV4?
    var v6: DhcpConfigV6?
}

/// Dekodowane „zwykłym” dekoderem (klucze = nazwy interfejsów).
struct DHCPNetInterface: Codable, Equatable {
    var flags: String?
    var gatewayIp: String?
    var hardwareAddress: String?
    var ipv4Addresses: [String]?
    var ipv6Addresses: [String]?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case flags
        case gatewayIp = "gateway_ip"
        case hardwareAddress = "hardware_address"
        case ipv4Addresses = "ipv4_addresses"
        case ipv6Addresses = "ipv6_addresses"
        case name
    }
}

typealias DHCPNetInterfaces = [String: DHCPNetInterface]

struct DhcpFindActiveReq: Codable, Equatable { var interface: String }

struct DhcpSearchResultOtherServer: Codable, Equatable {
    var found: String?
    var error: String?
}

struct DhcpSearchResultStaticIP: Codable, Equatable {
    var `static`: String?
    var ip: String?
}

struct DhcpSearchV4: Codable, Equatable {
    var otherServer: DhcpSearchResultOtherServer?
    var staticIp: DhcpSearchResultStaticIP?
}

struct DhcpSearchV6: Codable, Equatable { var otherServer: DhcpSearchResultOtherServer? }

struct DhcpSearchResult: Codable, Equatable {
    var v4: DhcpSearchV4?
    var v6: DhcpSearchV6?
}

// MARK: - TLS

struct TlsConfig: Codable, Equatable {
    var enabled: Bool?
    var serverName: String?
    var forceHttps: Bool?
    var portHttps: Int?
    var portDnsOverTls: Int?
    var portDnsOverQuic: Int?
    var certificateChain: String?
    var privateKey: String?
    var privateKeySaved: Bool?
    var certificatePath: String?
    var privateKeyPath: String?
    var validCert: Bool?
    var validChain: Bool?
    var subject: String?
    var issuer: String?
    var notBefore: String?
    var notAfter: String?
    var dnsNames: [String]?
    var validKey: Bool?
    var keyType: String?
    var warningValidation: String?
    var validPair: Bool?
    var servePlainDns: Bool?
    var portDnscrypt: Int?
    var dnscryptConfigFile: String?
}
