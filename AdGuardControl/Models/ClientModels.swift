import Foundation

typealias WhoisInfo = [String: String]

struct Client: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var ids: [String]?
    var useGlobalSettings: Bool?
    var filteringEnabled: Bool?
    var parentalEnabled: Bool?
    var safebrowsingEnabled: Bool?
    var safeSearch: SafeSearchConfig?
    var useGlobalBlockedServices: Bool?
    var blockedServicesSchedule: Schedule?
    var blockedServices: [String]?
    var upstreams: [String]?
    var tags: [String]?
    var ignoreQuerylog: Bool?
    var ignoreStatistics: Bool?
    var upstreamsCacheEnabled: Bool?
    var upstreamsCacheSize: Int?

    var id: String { name }

    static func new() -> Client {
        Client(name: "", ids: [], useGlobalSettings: true, filteringEnabled: true, parentalEnabled: false,
               safebrowsingEnabled: false, safeSearch: SafeSearchConfig(enabled: false),
               useGlobalBlockedServices: true, blockedServices: [], upstreams: [], tags: [],
               ignoreQuerylog: false, ignoreStatistics: false)
    }
}

struct ClientAuto: Codable, Equatable, Hashable, Identifiable {
    var ip: String
    var name: String?
    var source: String?
    var whoisInfo: WhoisInfo?
    var id: String { ip }
}

struct Clients: Codable, Equatable {
    var clients: [Client]?
    var autoClients: [ClientAuto]?
    var supportedTags: [String]?
}

struct ClientUpdate: Codable, Equatable {
    var name: String
    var data: Client
}

struct ClientDelete: Codable, Equatable { var name: String }

struct ClientsSearchRequestItem: Codable, Equatable { var id: String }
struct ClientsSearchRequest: Codable, Equatable { var clients: [ClientsSearchRequestItem] }

/// Wynik `/clients/search` – dekodowany „zwykłym” dekoderem (kluczami map są ID klientów).
struct ClientFindSubEntry: Codable, Equatable {
    var name: String?
    var ids: [String]?
    var filteringEnabled: Bool?
    var parentalEnabled: Bool?
    var safebrowsingEnabled: Bool?
    var whoisInfo: WhoisInfo?
    var disallowed: Bool?
    var disallowedRule: String?

    enum CodingKeys: String, CodingKey {
        case name, ids
        case filteringEnabled = "filtering_enabled"
        case parentalEnabled = "parental_enabled"
        case safebrowsingEnabled = "safebrowsing_enabled"
        case whoisInfo = "whois_info"
        case disallowed
        case disallowedRule = "disallowed_rule"
    }
}

typealias ClientsFindResponse = [[String: ClientFindSubEntry]]

struct AccessList: Codable, Equatable {
    var allowedClients: [String]?
    var disallowedClients: [String]?
    var blockedHosts: [String]?

    var allowed: [String] { allowedClients ?? [] }
    var disallowed: [String] { disallowedClients ?? [] }
    var blocked: [String] { blockedHosts ?? [] }
}
