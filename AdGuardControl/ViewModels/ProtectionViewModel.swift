import Foundation

@MainActor
final class ProtectionViewModel: BaseViewModel {
    @Published var status: ServerStatus?
    @Published var filtering: FilterStatus?
    @Published var safeBrowsing = false
    @Published var parental: ParentalStatus?
    @Published var safeSearch: SafeSearchConfig?
    @Published var services: [BlockedService] = []
    @Published var blocked: BlockedServicesSchedule = BlockedServicesSchedule()
    @Published var checkResult: FilterCheckHostResponse?
    @Published var checkError: String?

    override func refresh() async {
        await load { api in
            async let status = api.status()
            async let filtering = api.filteringStatus()
            async let safeBrowsing = api.safeBrowsingStatus()
            async let parental = api.parentalStatus()
            async let safeSearch = api.safeSearchStatus()
            async let services = api.allBlockedServices()
            async let blocked = api.blockedServices()
            let result = try await (status, filtering, safeBrowsing, parental, safeSearch, services, blocked)
            self.status = result.0
            self.filtering = result.1
            self.safeBrowsing = result.2.enabled
            self.parental = result.3
            self.safeSearch = result.4
            self.services = result.5.blockedServices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.blocked = result.6
        }
    }

    func setProtection(enabled: Bool, durationMs: UInt64? = nil) async {
        if await changeProtection(enabled: enabled, durationMs: durationMs) { await refresh() }
    }

    func setFiltering(enabled: Bool) async {
        if await changeFiltering(enabled: enabled, message: enabled ? "Filtrowanie włączone" : "Filtrowanie wyłączone") {
            await refresh()
        }
    }

    func setSafeBrowsing(_ enabled: Bool) async {
        let ok = await mutate(enabled ? "Bezpieczne przeglądanie włączone" : "Bezpieczne przeglądanie wyłączone",
                              undo: { try await $0.setSafeBrowsing(!enabled) }) {
            try await $0.setSafeBrowsing(enabled)
        }
        if ok { await refresh() }
    }

    func setParental(_ enabled: Bool) async {
        let ok = await mutate(enabled ? "Kontrola rodzicielska włączona" : "Kontrola rodzicielska wyłączona",
                              undo: { try await $0.setParental(!enabled) }) {
            try await $0.setParental(enabled)
        }
        if ok { await refresh() }
    }

    func updateSafeSearch(_ change: (inout SafeSearchConfig) -> Void, message: String) async {
        guard let previous = safeSearch else { return }
        var updated = previous
        change(&updated)
        let ok = await mutate(message, undo: { try await $0.setSafeSearch(previous) }) {
            try await $0.setSafeSearch(updated)
        }
        if ok { await refresh() }
    }

    func setService(_ id: String, blocked isBlocked: Bool) async {
        let previous = blocked
        var ids = Set(previous.ids ?? [])
        if isBlocked { ids.insert(id) } else { ids.remove(id) }
        let updated = BlockedServicesSchedule(schedule: previous.schedule, ids: ids.sorted())
        let name = services.first { $0.id == id }?.name ?? id
        let ok = await mutate(isBlocked ? "Zablokowano: \(name)" : "Odblokowano: \(name)",
                              undo: { try await $0.setBlockedServices(previous) }) {
            try await $0.setBlockedServices(updated)
        }
        if ok { blocked = updated }
    }

    func check(host: String, client: String?) async {
        checkResult = nil
        checkError = nil
        guard let api else { return }
        do {
            checkResult = try await api.checkHost(name: host.trimmingCharacters(in: .whitespaces), client: client)
        } catch {
            checkError = Self.apiError(from: error).errorDescription
        }
    }
}
