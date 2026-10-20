import Foundation

@MainActor
final class ClientsViewModel: BaseViewModel {
    @Published var clients: [Client] = []
    @Published var autoClients: [ClientAuto] = []
    @Published var supportedTags: [String] = []
    @Published var access = AccessList()
    @Published var queryCounts: [String: Int] = [:]
    @Published var availableServices: [BlockedService] = []

    override func refresh() async {
        await load { api in
            async let clients = api.clients()
            async let access = api.accessList()
            async let stats = api.stats()
            let (c, a, s) = try await (clients, access, stats)
            self.clients = (c.clients ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.autoClients = c.autoClients ?? []
            self.supportedTags = c.supportedTags ?? []
            self.access = a
            var counts: [String: Int] = [:]
            for entry in TopEntry.entries(s.topClients) { counts[entry.name] = Int(entry.value) }
            self.queryCounts = counts
        }
    }

    /// Lista usług (ok. 290 KB) jest potrzebna tylko w edytorze klienta – ładujemy ją na żądanie.
    func loadServicesIfNeeded() async {
        guard availableServices.isEmpty, let api else { return }
        if let all = try? await api.allBlockedServices() { availableServices = all.blockedServices }
    }

    func isBlocked(_ client: Client) -> Bool {
        let ids = Set(client.ids ?? [])
        return !ids.isDisjoint(with: access.disallowed)
    }

    func isBlocked(ip: String) -> Bool { access.disallowed.contains(ip) }

    func queries(for client: Client) -> Int {
        (client.ids ?? []).reduce(0) { $0 + (queryCounts[$1] ?? 0) }
    }

    func save(_ client: Client, replacing originalName: String?) async -> Bool {
        let ok: Bool
        if let originalName {
            let previous = clients.first { $0.name == originalName }
            ok = await mutate("Zapisano klienta „\(client.name)”",
                              undo: previous.map { old in { try await $0.updateClient(name: client.name, data: old) } }) {
                try await $0.updateClient(name: originalName, data: client)
            }
        } else {
            ok = await mutate("Dodano klienta „\(client.name)”", undo: { try await $0.deleteClient(name: client.name) }) {
                try await $0.addClient(client)
            }
        }
        if ok { await refresh() }
        return ok
    }

    func delete(_ client: Client) async {
        let ok = await mutate("Usunięto klienta „\(client.name)”", undo: { try await $0.addClient(client) }) {
            try await $0.deleteClient(name: client.name)
        }
        if ok { await refresh() }
    }

    /// Blokowanie klienta = dopisanie jego identyfikatorów do `disallowed_clients`.
    func setBlocked(ids: [String], blocked: Bool, label: String) async {
        // Lista dostępu jest pobierana tuż przed zapisem, żeby nie nadpisać zmian z ekranu „Kontrola dostępu”.
        var previous: AccessList?
        let ok = await mutate(blocked ? "Zablokowano klienta \(label)" : "Odblokowano klienta \(label)",
                              undo: { api in if let previous { try await api.setAccessList(previous) } }) { api in
            previous = try await api.modifyAccessList { list in
                var disallowed = Set(list.disallowed)
                if blocked { ids.forEach { disallowed.insert($0) } } else { ids.forEach { disallowed.remove($0) } }
                list.disallowedClients = disallowed.sorted()
            }
        }
        if ok, let fresh = try? await api?.accessList() { access = fresh }
    }

    /// Ostatnie zapytania danego klienta (do ekranu szczegółów).
    func recentQueries(for ids: [String]) async -> [QueryLogItem] {
        guard let api, let id = ids.first else { return [] }
        let log = try? await api.queryLog(QueryLogParams(limit: 20, search: id))
        return log?.data ?? []
    }
}
