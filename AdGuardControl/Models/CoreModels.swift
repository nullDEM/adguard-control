import Foundation

// MARK: - Profil serwera (UserDefaults; hasło wyłącznie w Keychain)

struct ServerProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Znormalizowany adres z portem, np. `http://100.64.0.5:3000`.
    var address: String
    var username: String
    var requireTailscale = false

    var url: URL? { URL(string: address) }
    var host: String { url?.host ?? address }
    var port: Int? { url?.port }
}

// MARK: - Status / ochrona

struct ServerStatus: Codable, Equatable {
    var dnsAddresses: [String]?
    var dnsPort: Int?
    var httpPort: Int?
    var protectionEnabled: Bool
    var protectionDisabledDuration: Int64?
    var dhcpAvailable: Bool?
    var running: Bool?
    var version: String
    var language: String?
    var startTime: Double?
}

struct SetProtectionRequest: Codable, Equatable {
    var enabled: Bool
    /// Czas pauzy w milisekundach (tylko gdy `enabled == false`).
    var duration: UInt64?
}

struct EnabledStatus: Codable, Equatable {
    var enabled: Bool
}

struct ParentalStatus: Codable, Equatable {
    var enabled: Bool
    var sensitivity: Int?
}

struct SafeSearchConfig: Codable, Equatable, Hashable {
    var enabled: Bool?
    var bing: Bool?
    var duckduckgo: Bool?
    var ecosia: Bool?
    var google: Bool?
    var pixabay: Bool?
    var yandex: Bool?
    var youtube: Bool?

    static let engines: [(name: String, keyPath: WritableKeyPath<SafeSearchConfig, Bool?>)] = [
        ("Bing", \.bing), ("DuckDuckGo", \.duckduckgo), ("Ecosia", \.ecosia), ("Google", \.google),
        ("Pixabay", \.pixabay), ("Yandex", \.yandex), ("YouTube", \.youtube)
    ]
}

struct ProfileInfo: Codable, Equatable {
    var name: String
    var language: String
    var theme: String
}

struct VersionInfo: Codable, Equatable {
    var disabled: Bool
    var newVersion: String?
    var announcement: String?
    var announcementUrl: String?
    var canAutoupdate: Bool?
}

struct GetVersionRequest: Codable { var recheckNow: Bool }

// MARK: - Statystyki

/// Odpowiedź `/stats` – dekodowana „zwykłym” dekoderem (klucze map to nazwy domen/IP).
struct Stats: Codable, Equatable {
    var timeUnits: String?
    var numDnsQueries: Int?
    var numBlockedFiltering: Int?
    var numReplacedSafebrowsing: Int?
    var numReplacedSafesearch: Int?
    var numReplacedParental: Int?
    var avgProcessingTime: Double?
    var topQueriedDomains: [[String: Double]]?
    var topClients: [[String: Double]]?
    var topBlockedDomains: [[String: Double]]?
    var topUpstreamsResponses: [[String: Double]]?
    var topUpstreamsAvgTime: [[String: Double]]?
    var dnsQueries: [Int]?
    var blockedFiltering: [Int]?
    var replacedSafebrowsing: [Int]?
    var replacedParental: [Int]?

    enum CodingKeys: String, CodingKey {
        case timeUnits = "time_units"
        case numDnsQueries = "num_dns_queries"
        case numBlockedFiltering = "num_blocked_filtering"
        case numReplacedSafebrowsing = "num_replaced_safebrowsing"
        case numReplacedSafesearch = "num_replaced_safesearch"
        case numReplacedParental = "num_replaced_parental"
        case avgProcessingTime = "avg_processing_time"
        case topQueriedDomains = "top_queried_domains"
        case topClients = "top_clients"
        case topBlockedDomains = "top_blocked_domains"
        case topUpstreamsResponses = "top_upstreams_responses"
        case topUpstreamsAvgTime = "top_upstreams_avg_time"
        case dnsQueries = "dns_queries"
        case blockedFiltering = "blocked_filtering"
        case replacedSafebrowsing = "replaced_safebrowsing"
        case replacedParental = "replaced_parental"
    }

    var totalQueries: Int { numDnsQueries ?? 0 }
    var totalBlocked: Int {
        (numBlockedFiltering ?? 0) + (numReplacedSafebrowsing ?? 0) + (numReplacedParental ?? 0)
    }
    var blockedPercent: Double {
        totalQueries == 0 ? 0 : Double(totalBlocked) / Double(totalQueries) * 100
    }
    var activeClients: Int { topClients?.count ?? 0 }
}

struct TopEntry: Identifiable, Equatable {
    let name: String
    let value: Double
    var id: String { name }

    static func entries(_ raw: [[String: Double]]?) -> [TopEntry] {
        (raw ?? []).flatMap { $0.map { TopEntry(name: $0.key, value: $0.value) } }
    }
}

struct StatsConfig: Codable, Equatable {
    var enabled: Bool
    /// Czas przechowywania w milisekundach.
    var interval: Double
    var ignored: [String]
    var ignoredEnabled: Bool?

    static let intervalDays: [Int] = [1, 7, 30, 90]
    var days: Int { Int(interval / 86_400_000) }
}

struct QueryLogConfig: Codable, Equatable {
    var enabled: Bool
    var interval: Double
    var anonymizeClientIp: Bool
    var ignored: [String]
    var ignoredEnabled: Bool?

    var days: Double { interval / 86_400_000 }
}

// MARK: - Query log

struct DnsAnswer: Codable, Equatable, Hashable {
    var ttl: Int?
    var type: String?
    var value: String?
}

struct DnsQuestion: Codable, Equatable, Hashable {
    var `class`: String?
    var name: String?
    var unicodeName: String?
    var type: String?
}

struct ResultRule: Codable, Equatable, Hashable {
    var filterListId: Int64?
    var text: String?
}

struct QueryLogClientWhois: Codable, Equatable, Hashable {
    var city: String?
    var country: String?
    var orgname: String?
}

struct QueryLogClientInfo: Codable, Equatable, Hashable {
    var disallowed: Bool?
    var disallowedRule: String?
    var name: String?
    var whois: QueryLogClientWhois?
}

struct QueryLogItem: Codable, Equatable, Hashable, Identifiable {
    var uid = UUID()
    var answer: [DnsAnswer]?
    var originalAnswer: [DnsAnswer]?
    var cached: Bool?
    var upstream: String?
    var answerDnssec: Bool?
    var client: String?
    var clientId: String?
    var clientInfo: QueryLogClientInfo?
    var clientProto: String?
    var ecs: String?
    var elapsedMs: String?
    var question: DnsQuestion?
    var rules: [ResultRule]?
    var reason: String?
    var serviceName: String?
    var status: String?
    var time: String?

    var id: UUID { uid }

    enum CodingKeys: String, CodingKey {
        case answer, originalAnswer, cached, upstream, answerDnssec, client, clientId, clientInfo
        case clientProto, ecs, elapsedMs, question, rules, reason, serviceName, status, time
    }

    var domain: String { question?.name ?? "—" }
    var kind: QueryKind { QueryKind(reason: reason) }
    var clientDisplayName: String {
        if let name = clientInfo?.name, !name.isEmpty { return name }
        return client ?? "—"
    }
}

struct QueryLog: Codable, Equatable {
    var oldest: String?
    var data: [QueryLogItem]?
}

/// Pogrupowany powód filtrowania – do kolorowania i filtrowania.
enum QueryKind: Equatable {
    case allowed, blocked, whitelisted, safeBrowsing, parental, safeSearch, rewritten, blockedService, error

    init(reason: String?) {
        switch reason ?? "" {
        case "FilteredBlackList", "FilteredInvalid": self = .blocked
        case "FilteredBlockedService": self = .blockedService
        case "FilteredSafeBrowsing": self = .safeBrowsing
        case "FilteredParental": self = .parental
        case "FilteredSafeSearch": self = .safeSearch
        case "NotFilteredWhiteList": self = .whitelisted
        case "Rewrite", "RewriteEtcHosts", "RewriteRule": self = .rewritten
        case "NotFilteredError": self = .error
        default: self = .allowed
        }
    }

    var title: String {
        switch self {
        case .allowed: return "Przetworzone"
        case .blocked: return "Zablokowane"
        case .whitelisted: return "Na białej liście"
        case .safeBrowsing: return "Bezpieczne przeglądanie"
        case .parental: return "Kontrola rodzicielska"
        case .safeSearch: return "Bezpieczne wyszukiwanie"
        case .rewritten: return "Przepisane"
        case .blockedService: return "Zablokowana usługa"
        case .error: return "Błąd filtrowania"
        }
    }

    var isBlocked: Bool {
        switch self {
        case .blocked, .safeBrowsing, .parental, .blockedService: return true
        default: return false
        }
    }
}

/// Filtr statusu w Query Log – mapowany na parametr `reason` (zgodnie z OpenAPI).
enum QueryStatusFilter: String, CaseIterable, Identifiable {
    case all, blocked, safeBrowsing, parental, whitelisted, rewritten, safeSearch, processed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Wszystkie"
        case .blocked: return "Zablokowane"
        case .safeBrowsing: return "Bezp. przeglądanie"
        case .parental: return "Rodzicielska"
        case .whitelisted: return "Dozwolone (biała lista)"
        case .rewritten: return "Przepisane"
        case .safeSearch: return "Bezp. wyszukiwanie"
        case .processed: return "Przetworzone"
        }
    }

    var reasons: [String] {
        switch self {
        case .all: return []
        case .blocked: return ["FilteredBlackList", "FilteredBlockedService", "FilteredInvalid"]
        case .safeBrowsing: return ["FilteredSafeBrowsing"]
        case .parental: return ["FilteredParental"]
        case .whitelisted: return ["NotFilteredWhiteList"]
        case .rewritten: return ["Rewrite", "RewriteEtcHosts", "RewriteRule"]
        case .safeSearch: return ["FilteredSafeSearch"]
        case .processed: return ["NotFilteredNotFound"]
        }
    }
}

/// Zakres czasu stosowany po stronie aplikacji (API nie ma filtra czasu).
enum QueryTimeRange: String, CaseIterable, Identifiable {
    case all, hour, day, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Cały czas"
        case .hour: return "Ostatnia godzina"
        case .day: return "Ostatnie 24 h"
        case .week: return "Ostatnie 7 dni"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .all: return nil
        case .hour: return 3600
        case .day: return 86_400
        case .week: return 604_800
        }
    }
}

struct QueryLogParams: Equatable {
    var olderThan: String?
    var offset: Int?
    var limit: Int = 50
    var search: String?
    var reasons: [String] = []

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let olderThan, !olderThan.isEmpty { items.append(.init(name: "older_than", value: olderThan)) }
        if let offset { items.append(.init(name: "offset", value: String(offset))) }
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        for reason in reasons { items.append(.init(name: "reason", value: reason)) }
        return items
    }
}
