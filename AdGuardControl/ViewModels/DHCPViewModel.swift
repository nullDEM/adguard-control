import Foundation

@MainActor
final class DHCPViewModel: BaseViewModel {
    @Published var status: DhcpStatus?
    @Published var interfaces: DHCPNetInterfaces = [:]
    @Published var draft = DhcpConfig(enabled: false, interfaceName: "", v4: nil, v6: nil)
    @Published var searchResult: DhcpSearchResult?
    @Published var unavailableMessage: String?

    static func config(of status: DhcpStatus) -> DhcpConfig {
        DhcpConfig(enabled: status.enabled, interfaceName: status.interfaceName, v4: status.v4, v6: status.v6)
    }

    var isDirty: Bool {
        guard let status else { return false }
        return draft != Self.config(of: status)
    }

    var leases: [DhcpLease] { status?.leases ?? [] }
    var staticLeases: [DhcpStaticLease] { status?.staticLeases ?? [] }

    override func refresh() async {
        unavailableMessage = nil
        await load { api in
            async let status = api.dhcpStatus()
            async let interfaces = api.dhcpInterfaces()
            let (s, i) = try await (status, interfaces)
            self.status = s
            self.interfaces = i
            self.draft = DhcpConfig(enabled: s.enabled, interfaceName: s.interfaceName, v4: s.v4, v6: s.v6)
        }
        if case .failed(let error) = state, case .server(let code, let message) = error, code >= 500 {
            unavailableMessage = message
        } else if case .failed(.notImplemented(let message)) = state {
            unavailableMessage = message
        }
    }

    func save() async -> Bool {
        let previous = status.map { Self.config(of: $0) }
        let new = draft
        var conflict = false
        let ok = await mutate("Zapisano konfigurację DHCP", undo: previous.map { old in { try await $0.dhcpSetConfig(old) } }) { api in
            // Nie nadpisujemy konfiguracji zmienionej na serwerze od momentu wczytania.
            if let previous, Self.config(of: try await api.dhcpStatus()) != previous {
                conflict = true
                throw APIError.conflict("Konfiguracja DHCP została zmieniona na serwerze od momentu wczytania. Odświeżyłem dane – sprawdź i zapisz ponownie.")
            }
            try await api.dhcpSetConfig(new)
        }
        if ok || conflict { await refresh() }
        return ok
    }

    func setEnabled(_ enabled: Bool) async {
        draft.enabled = enabled
        _ = await save()
    }

    func findActiveServers() async {
        guard let api, !draft.interfaceName.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            searchResult = try await api.dhcpFindActive(interface: draft.interfaceName)
        } catch {
            app?.notifyError(Self.apiError(from: error))
        }
    }

    func addStatic(_ lease: DhcpStaticLease) async -> Bool {
        let ok = await mutate("Dodano statyczną dzierżawę \(lease.ip)", undo: { try await $0.dhcpRemoveStaticLease(lease) }) {
            try await $0.dhcpAddStaticLease(lease)
        }
        if ok { await refresh() }
        return ok
    }

    func updateStatic(_ lease: DhcpStaticLease, previous: DhcpStaticLease) async -> Bool {
        let ok = await mutate("Zapisano dzierżawę \(lease.ip)", undo: { try await $0.dhcpUpdateStaticLease(previous) }) {
            try await $0.dhcpUpdateStaticLease(lease)
        }
        if ok { await refresh() }
        return ok
    }

    func removeStatic(_ lease: DhcpStaticLease) async {
        let ok = await mutate("Usunięto dzierżawę \(lease.ip)", undo: { try await $0.dhcpAddStaticLease(lease) }) {
            try await $0.dhcpRemoveStaticLease(lease)
        }
        if ok { await refresh() }
    }

    func makeStatic(from lease: DhcpLease) async {
        _ = await addStatic(DhcpStaticLease(mac: lease.mac, ip: lease.ip, hostname: lease.hostname))
    }

    func resetLeases() async {
        let ok = await mutate("Wyczyszczono dzierżawy DHCP") { try await $0.dhcpResetLeases() }
        if ok { await refresh() }
    }

    func resetAll() async {
        let ok = await mutate("Zresetowano konfigurację DHCP") { try await $0.dhcpReset() }
        if ok { await refresh() }
    }
}
