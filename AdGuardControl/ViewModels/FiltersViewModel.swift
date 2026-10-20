import Foundation

@MainActor
final class FiltersViewModel: BaseViewModel {
    @Published var status: FilterStatus?
    @Published var rewrites: [RewriteEntry] = []
    @Published var rewritesEnabled = true

    var blocklists: [Filter] { status?.filters ?? [] }
    var allowlists: [Filter] { status?.whitelistFilters ?? [] }
    var userRuleLines: [String] { status?.userRules ?? [] }
    var userRules: [UserRule] { UserRule.parse(userRuleLines) }

    override func refresh() async {
        await load { api in
            async let status = api.filteringStatus()
            async let rewrites = api.rewrites()
            async let settings = api.rewriteSettings()
            let (s, r, rs) = try await (status, rewrites, settings)
            self.status = s
            self.rewrites = r
            self.rewritesEnabled = rs.enabled
        }
    }

    private func reloadStatus() async {
        if let api, let status = try? await api.filteringStatus() { self.status = status }
    }

    // MARK: Ustawienia globalne filtrowania

    func setFilteringEnabled(_ enabled: Bool) async {
        if await changeFiltering(enabled: enabled, message: enabled ? "Filtrowanie włączone" : "Filtrowanie wyłączone") {
            await reloadStatus()
        }
    }

    func setInterval(_ hours: Int) async {
        if await changeFiltering(interval: hours, message: "Interwał aktualizacji: \(hours) godz.") {
            await reloadStatus()
        }
    }

    // MARK: Listy filtrów

    func addFilter(name: String, url: String, whitelist: Bool) async -> Bool {
        let ok = await mutate("Dodano listę „\(name)”", undo: { try await $0.removeFilter(url: url, whitelist: whitelist) }) {
            try await $0.addFilter(name: name, url: url, whitelist: whitelist)
        }
        if ok { await reloadStatus() }
        return ok
    }

    func updateFilter(_ filter: Filter, name: String, url: String, enabled: Bool, whitelist: Bool) async -> Bool {
        let ok = await mutate("Zapisano listę „\(name)”",
                              undo: { try await $0.updateFilter(url: url, name: filter.name, newURL: filter.url,
                                                               enabled: filter.enabled, whitelist: whitelist) }) {
            try await $0.updateFilter(url: filter.url, name: name, newURL: url, enabled: enabled, whitelist: whitelist)
        }
        if ok { await reloadStatus() }
        return ok
    }

    func setFilter(_ filter: Filter, enabled: Bool, whitelist: Bool) async {
        _ = await updateFilter(filter, name: filter.name, url: filter.url, enabled: enabled, whitelist: whitelist)
    }

    func removeFilter(_ filter: Filter, whitelist: Bool) async {
        let ok = await mutate("Usunięto listę „\(filter.name)”",
                              undo: { api in
                                  try await api.addFilter(name: filter.name, url: filter.url, whitelist: whitelist)
                                  if !filter.enabled {
                                      try await api.updateFilter(url: filter.url, name: filter.name, newURL: filter.url,
                                                                 enabled: false, whitelist: whitelist)
                                  }
                              }) {
            try await $0.removeFilter(url: filter.url, whitelist: whitelist)
        }
        if ok { await reloadStatus() }
    }

    /// Wymusza pobranie aktualnych wersji list; zwraca liczbę zaktualizowanych.
    func refreshFilters(whitelist: Bool) async {
        var updated = 0
        let ok = await mutate(nil) { updated = try await $0.refreshFilters(whitelist: whitelist) }
        guard ok else { return }
        app?.notify(updated == 0 ? "Wszystkie listy są aktualne" : "Zaktualizowano list: \(updated)")
        await reloadStatus()
    }

    // MARK: Własne reguły
    //
    // Każda zmiana pobiera aktualne reguły z serwera i modyfikuje wskazaną regułę po jej treści,
    // dzięki czemu nie nadpisujemy reguł dodanych w międzyczasie (np. szybkim blokowaniem z Query Log).

    private func applyRules(_ message: String, _ transform: @escaping ([String]) throws -> [String]?) async -> Bool {
        var previous: [String] = []
        let ok = await mutate(message, undo: { try await $0.setUserRules(previous) }) { api in
            var failure: Error?
            previous = try await api.modifyUserRules { lines in
                do { return try transform(lines) } catch { failure = error; return nil }
            }
            if let failure { throw failure }
        }
        if ok { await reloadStatus() }
        return ok
    }

    /// Indeks reguły w aktualnej liście: najpierw ten sam indeks, potem pierwsza linia o tej samej treści.
    private static func index(of rule: UserRule, in lines: [String]) throws -> Int {
        if lines.indices.contains(rule.id), lines[rule.id] == rule.text { return rule.id }
        if let index = lines.firstIndex(of: rule.text) { return index }
        throw APIError.conflict("Reguła została zmieniona na serwerze. Dane odświeżono – spróbuj ponownie.")
    }

    func addRule(_ text: String) async -> Bool {
        let rule = text.trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty else { return false }
        return await applyRules("Dodano regułę") { lines in lines.contains(rule) ? nil : lines + [rule] }
    }

    func editRule(_ rule: UserRule, to text: String) async -> Bool {
        let newText = text.trimmingCharacters(in: .whitespaces)
        guard !newText.isEmpty else { return false }
        let ok = await applyRules("Zapisano regułę") { lines in
            var lines = lines
            lines[try Self.index(of: rule, in: lines)] = newText
            return lines
        }
        if !ok { await reloadStatus() }
        return ok
    }

    func deleteRule(_ rule: UserRule) async {
        let ok = await applyRules("Usunięto regułę") { lines in
            var lines = lines
            lines.remove(at: try Self.index(of: rule, in: lines))
            return lines
        }
        if !ok { await reloadStatus() }
    }

    func toggleRule(_ rule: UserRule) async {
        let ok = await applyRules(rule.isEnabled ? "Wyłączono regułę" : "Włączono regułę") { lines in
            var lines = lines
            lines[try Self.index(of: rule, in: lines)] = rule.toggled()
            return lines
        }
        if !ok { await reloadStatus() }
    }

    func replaceAllRules(with lines: [String]) async -> Bool {
        await applyRules("Zapisano reguły") { _ in lines }
    }

    // MARK: DNS rewrites

    private func reloadRewrites() async {
        if let api, let list = try? await api.rewrites() { rewrites = list }
    }

    func addRewrite(domain: String, answer: String) async -> Bool {
        let entry = RewriteEntry(domain: domain, answer: answer, enabled: true)
        let ok = await mutate("Dodano przepisanie \(domain)", undo: { try await $0.deleteRewrite(entry) }) {
            try await $0.addRewrite(entry)
        }
        if ok { await reloadRewrites() }
        return ok
    }

    func updateRewrite(_ target: RewriteEntry, domain: String, answer: String, enabled: Bool) async -> Bool {
        let update = RewriteEntry(domain: domain, answer: answer, enabled: enabled)
        let ok = await mutate("Zapisano przepisanie",
                              undo: { try await $0.updateRewrite(target: update, update: target) }) {
            try await $0.updateRewrite(target: target, update: update)
        }
        if ok { await reloadRewrites() }
        return ok
    }

    func deleteRewrite(_ entry: RewriteEntry) async {
        let ok = await mutate("Usunięto przepisanie \(entry.domain)", undo: { try await $0.addRewrite(entry) }) {
            try await $0.deleteRewrite(entry)
        }
        if ok { await reloadRewrites() }
    }

    func setRewritesEnabled(_ enabled: Bool) async {
        let ok = await mutate(enabled ? "Przepisywanie DNS włączone" : "Przepisywanie DNS wyłączone",
                              undo: { try await $0.setRewriteSettings(RewriteSettings(enabled: !enabled)) }) {
            try await $0.setRewriteSettings(RewriteSettings(enabled: enabled))
        }
        if ok { rewritesEnabled = enabled }
    }
}
