import Foundation

struct Filter: Codable, Equatable, Hashable, Identifiable {
    var enabled: Bool
    var id: Int64
    var lastUpdated: String?
    var name: String
    var rulesCount: Int
    var url: String
}

struct FilterStatus: Codable, Equatable {
    var enabled: Bool?
    var interval: Int?
    var filters: [Filter]?
    var whitelistFilters: [Filter]?
    var userRules: [String]?
}

struct FilterConfig: Codable, Equatable {
    var enabled: Bool?
    var interval: Int?
}

struct AddUrlRequest: Codable, Equatable {
    var name: String
    var url: String
    var whitelist: Bool
}

struct RemoveUrlRequest: Codable, Equatable {
    var url: String
    var whitelist: Bool
}

struct FilterSetUrlData: Codable, Equatable {
    var enabled: Bool
    var name: String
    var url: String
}

struct FilterSetUrl: Codable, Equatable {
    var data: FilterSetUrlData
    var url: String
    var whitelist: Bool
}

struct FilterRefreshRequest: Codable, Equatable { var whitelist: Bool }
struct FilterRefreshResponse: Codable, Equatable { var updated: Int? }
struct SetRulesRequest: Codable, Equatable { var rules: [String] }

struct FilterCheckHostResponse: Codable, Equatable {
    var reason: String?
    var rules: [ResultRule]?
    var serviceName: String?
    var cname: String?
    var ipAddrs: [String]?
}

/// Pojedyncza linia „własnych reguł filtrowania”.
struct UserRule: Identifiable, Equatable {
    enum Kind: Equatable { case block, allow, comment, disabled, other }

    var id: Int          // indeks linii w pliku reguł
    var text: String

    var kind: Kind {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@@") { return .allow }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("!") {
            let body = UserRule.uncommented(trimmed)
            if body.hasPrefix("||") || body.hasPrefix("@@") || body.hasPrefix("|") { return .disabled }
            return .comment
        }
        if trimmed.hasPrefix("||") || trimmed.hasPrefix("|") || trimmed.hasPrefix("/") { return .block }
        return .other
    }

    var isEnabled: Bool { kind != .comment && kind != .disabled }

    static func uncommented(_ text: String) -> String {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        while let first = s.first, first == "#" || first == "!" { s = s.dropFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ lines: [String]) -> [UserRule] {
        lines.enumerated().compactMap { index, line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : UserRule(id: index, text: line)
        }
    }

    /// Dodaje/usuwa komentarz `! ` z początku reguły (wyłączenie / włączenie).
    func toggled() -> String {
        isEnabled ? "! " + text : UserRule.uncommented(text)
    }

    static func blockRule(domain: String) -> String { "||\(domain)^" }
    static func allowRule(domain: String) -> String { "@@||\(domain)^" }
}

struct RewriteEntry: Codable, Equatable, Hashable, Identifiable {
    var domain: String
    var answer: String
    var enabled: Bool?
    var id: String { domain + "→" + answer }
}

struct RewriteUpdate: Codable, Equatable {
    var target: RewriteEntry
    var update: RewriteEntry
}

struct RewriteSettings: Codable, Equatable { var enabled: Bool }

// MARK: - Zablokowane usługi

struct DayRange: Codable, Equatable, Hashable {
    var start: Double?
    var end: Double?
}

struct Schedule: Codable, Equatable, Hashable {
    var timeZone: String?
    var sun: DayRange?
    var mon: DayRange?
    var tue: DayRange?
    var wed: DayRange?
    var thu: DayRange?
    var fri: DayRange?
    var sat: DayRange?
}

struct BlockedServicesSchedule: Codable, Equatable {
    var schedule: Schedule?
    var ids: [String]?
}

struct BlockedService: Codable, Equatable, Identifiable {
    var iconSvg: String?
    var id: String
    var name: String
    var rules: [String]?
    var groupId: String?
}

struct ServiceGroup: Codable, Equatable { var id: String }

struct BlockedServicesAll: Codable, Equatable {
    var blockedServices: [BlockedService]
    var groups: [ServiceGroup]?
}
