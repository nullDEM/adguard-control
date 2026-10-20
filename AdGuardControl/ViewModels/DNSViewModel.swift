import Foundation

@MainActor
final class DNSViewModel: BaseViewModel {
    @Published var config = DNSConfig()
    @Published private(set) var original = DNSConfig()
    @Published var defaultPtrUpstreams: [String] = []
    @Published var testResults: [(server: String, result: String)] = []
    @Published var isTesting = false

    var isDirty: Bool { config != original }

    override func refresh() async {
        await load { api in
            let info = try await api.dnsInfo()
            self.config = info.config
            self.original = info.config
            self.defaultPtrUpstreams = info.defaultLocalPtrUpstreams
        }
    }

    func discardChanges() { config = original }

    /// Konfiguracja bez pól ochrony (zmienianych osobnym endpointem) – do zapisu i porównań.
    static func editable(_ config: DNSConfig) -> DNSConfig {
        var copy = config
        copy.protectionEnabled = nil
        copy.protectionDisabledUntil = nil
        return copy
    }

    func save() async -> Bool {
        let payload = Self.editable(config)
        let baseline = Self.editable(original)
        var conflict = false
        let ok = await mutate("Zapisano ustawienia DNS", undo: { try await $0.setDNSConfig(baseline) }) { api in
            // Zapis nadpisuje całą konfigurację, więc najpierw sprawdzamy, czy serwer nie zmienił się od wczytania.
            let fresh = Self.editable(try await api.dnsInfo().config)
            if fresh != baseline {
                conflict = true
                throw APIError.conflict("Konfiguracja DNS została zmieniona na serwerze od momentu wczytania. Odświeżyłem dane – sprawdź i zapisz ponownie.")
            }
            try await api.setDNSConfig(payload)
        }
        if ok || conflict { await refresh() }
        return ok
    }

    func testUpstreams() async {
        guard let api else { return }
        isTesting = true
        defer { isTesting = false }
        let request = UpstreamsConfig(bootstrapDns: config.bootstrapDns ?? [],
                                      upstreamDns: config.upstreamDns ?? [],
                                      fallbackDns: config.fallbackDns,
                                      privateUpstream: config.localPtrUpstreams)
        do {
            let response = try await api.testUpstreams(request)
            testResults = response.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } catch {
            app?.notifyError(Self.apiError(from: error))
        }
    }

    func clearCache() async {
        await mutate("Wyczyszczono pamięć podręczną DNS") { try await $0.clearCache() }
    }
}
