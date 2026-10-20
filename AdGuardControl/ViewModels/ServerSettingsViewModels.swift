import Foundation

/// Ustawienia ogólne: profil panelu, wersja, statystyki, query log, czyszczenie danych.
@MainActor
final class GeneralSettingsViewModel: BaseViewModel {
    @Published var status: ServerStatus?
    @Published var profile: ProfileInfo?
    @Published var version: VersionInfo?
    @Published var statsConfig: StatsConfig?
    @Published var queryLogConfig: QueryLogConfig?

    override func refresh() async {
        await load { api in
            async let status = api.status()
            async let profile = api.profile()
            async let stats = api.statsConfig()
            async let log = api.queryLogConfig()
            let (s, p, sc, qc) = try await (status, profile, stats, log)
            self.status = s
            self.profile = p
            self.statsConfig = sc
            self.queryLogConfig = qc
        }
    }

    func checkForUpdates() async {
        guard let api else { return }
        isBusy = true
        defer { isBusy = false }
        do { version = try await api.versionInfo(recheck: true) } catch { app?.notifyError(Self.apiError(from: error)) }
    }

    func beginUpdate() async {
        await mutate("Rozpoczęto aktualizację AdGuard Home") { try await $0.beginUpdate() }
    }

    func saveProfile(_ new: ProfileInfo) async {
        let old = profile
        let ok = await mutate("Zapisano profil panelu", undo: old.map { previous in { try await $0.updateProfile(previous) } }) {
            try await $0.updateProfile(new)
        }
        if ok { profile = new }
    }

    func saveStats(_ new: StatsConfig) async {
        let old = statsConfig
        let ok = await mutate("Zapisano ustawienia statystyk", undo: old.map { previous in { try await $0.setStatsConfig(previous) } }) {
            try await $0.setStatsConfig(new)
        }
        if ok { statsConfig = new }
    }

    func saveQueryLog(_ new: QueryLogConfig) async {
        let old = queryLogConfig
        let ok = await mutate("Zapisano ustawienia query log", undo: old.map { previous in { try await $0.setQueryLogConfig(previous) } }) {
            try await $0.setQueryLogConfig(new)
        }
        if ok { queryLogConfig = new }
    }

    func resetStats() async { await mutate("Wyczyszczono statystyki") { try await $0.resetStats() } }
    func clearQueryLog() async { await mutate("Wyczyszczono query log") { try await $0.clearQueryLog() } }
    func clearCache() async { await mutate("Wyczyszczono pamięć podręczną DNS") { try await $0.clearCache() } }
}

@MainActor
final class TLSViewModel: BaseViewModel {
    @Published var config = TlsConfig()
    @Published private(set) var original = TlsConfig()
    @Published var certificateText = ""
    @Published var privateKeyText = ""
    @Published var validation: TlsConfig?

    var isDirty: Bool { config != original || !certificateText.isEmpty || !privateKeyText.isEmpty }

    override func refresh() async {
        await load { api in
            let tls = try await api.tlsStatus()
            self.config = tls
            self.original = tls
        }
    }

    /// Konfiguracja do wysłania – certyfikat i klucz tylko gdy użytkownik wkleił nowe (base64 PEM).
    private func payload() -> TlsConfig {
        var payload = config
        if !certificateText.isEmpty { payload.certificateChain = Data(certificateText.utf8).base64EncodedString() }
        if !privateKeyText.isEmpty { payload.privateKey = Data(privateKeyText.utf8).base64EncodedString() }
        return payload
    }

    func validate() async {
        guard let api else { return }
        isBusy = true
        defer { isBusy = false }
        do { validation = try await api.tlsValidate(payload()) } catch { app?.notifyError(Self.apiError(from: error)) }
    }

    func save() async -> Bool {
        let body = payload()
        let baseline = original
        var result: TlsConfig?
        var conflict = false
        let ok = await mutate("Zapisano konfigurację HTTPS") { api in
            // Błędna konfiguracja TLS może odciąć dostęp do panelu – nie nadpisujemy zmian z serwera.
            if try await api.tlsStatus() != baseline {
                conflict = true
                throw APIError.conflict("Konfiguracja HTTPS została zmieniona na serwerze od momentu wczytania. Odświeżyłem dane – sprawdź i zapisz ponownie.")
            }
            result = try await api.tlsConfigure(body)
        }
        if conflict { certificateText = ""; privateKeyText = ""; await refresh() }
        if ok, let result {
            config = result
            original = result
            certificateText = ""
            privateKeyText = ""
            validation = nil
        }
        return ok
    }

    func discard() {
        config = original
        certificateText = ""
        privateKeyText = ""
        validation = nil
    }
}

@MainActor
final class AccessViewModel: BaseViewModel {
    @Published var list = AccessList()

    override func refresh() async {
        await load { self.list = try await $0.accessList() }
    }

    func save(_ new: AccessList) async -> Bool {
        let previous = list
        var conflict = false
        let ok = await mutate("Zapisano kontrolę dostępu", undo: { try await $0.setAccessList(previous) }) { api in
            if try await api.accessList() != previous {
                conflict = true
                throw APIError.conflict("Lista dostępu została zmieniona na serwerze od momentu wczytania. Odświeżyłem dane – sprawdź i zapisz ponownie.")
            }
            try await api.setAccessList(new)
        }
        if ok { list = new }
        if conflict { await refresh() }
        return ok
    }
}
