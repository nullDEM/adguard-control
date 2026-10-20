import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("appearance") private var appearance = "dark"

    var body: some View {
        Group {
            List {
                Section("Połączenie") {
                    NavigationLink {
                        ProfilesView()
                    } label: {
                        LabeledContent("Serwery") { Text(app.activeProfile?.name ?? "—").foregroundStyle(.secondary) }
                    }
                    if let profile = app.activeProfile {
                        LabeledContent("Adres", value: profile.address)
                        LabeledContent("Użytkownik", value: profile.username)
                        LabeledContent("Wymagaj Tailscale", value: profile.requireTailscale ? "Tak" : "Nie")
                    }
                    NavigationLink("Instrukcja Tailscale") { TailscaleHelpView() }
                }
                Section("Serwer AdGuard Home") {
                    NavigationLink { GeneralSettingsView() } label: { Label("Ustawienia ogólne", systemImage: "gearshape") }
                    NavigationLink { TLSView() } label: { Label("HTTPS / TLS", systemImage: "lock.shield") }
                    NavigationLink { AccessView() } label: { Label("Kontrola dostępu", systemImage: "person.badge.shield.checkmark") }
                }
                Section("Wygląd aplikacji") {
                    Picker("Motyw", selection: $appearance) {
                        Text("Ciemny").tag("dark")
                        Text("Jasny").tag("light")
                        Text("Systemowy").tag("system")
                    }
                }
                Section("Informacje") {
                    NavigationLink { CoverageView() } label: { Label("Zakres funkcji i API", systemImage: "checklist") }
                    LabeledContent("Wersja aplikacji", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Ustawienia")
        }
    }
}

// MARK: - Ustawienia ogólne

struct GeneralSettingsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = GeneralSettingsViewModel()
    @State private var stats = StatsConfig(enabled: true, interval: 86_400_000, ignored: [])
    @State private var queryLog = QueryLogConfig(enabled: true, interval: 86_400_000, anonymizeClientIp: false, ignored: [])
    @State private var ignoredStats = ""
    @State private var ignoredLog = ""
    @State private var profile = ProfileInfo(name: "", language: "en", theme: "auto")
    @State private var confirm: DangerAction?
    @State private var saveConfirm: SaveSection?

    enum DangerAction: Identifiable {
        case stats, log, cache, update
        var id: Int { hashValue }
        var title: String {
            switch self {
            case .stats: return "Wyczyścić statystyki?"
            case .log: return "Wyczyścić query log?"
            case .cache: return "Wyczyścić cache DNS?"
            case .update: return "Zaktualizować AdGuard Home?"
            }
        }
        var message: String {
            switch self {
            case .stats: return "Wszystkie statystyki zostaną trwale usunięte."
            case .log: return "Cała historia zapytań zostanie trwale usunięta."
            case .cache: return "Pamięć podręczna DNS zostanie opróżniona."
            case .update: return "Serwer pobierze nową wersję i uruchomi się ponownie. Połączenie na chwilę zniknie."
            }
        }
    }

    enum SaveSection: Identifiable { case stats, log, profile; var id: Int { hashValue } }

    private static let languages = ["ar", "be", "bg", "cs", "da", "de", "en", "es", "fa", "fi", "fr", "hr", "hu", "id", "it", "ja", "ko",
                                    "nl", "no", "pl", "pt-br", "pt-pt", "ro", "ru", "si-lk", "sk", "sl", "sr-cs", "sv", "th", "tr", "uk",
                                    "vi", "zh-cn", "zh-hk", "zh-tw"]

    var body: some View {
        LoadStateView(state: vm.state, retry: vm.refresh) {
            Form {
                Section {
                    LabeledContent("Wersja", value: vm.status?.version ?? "—")
                    LabeledContent("Adresy DNS", value: (vm.status?.dnsAddresses ?? []).joined(separator: ", "))
                    LabeledContent("Port DNS", value: vm.status?.dnsPort.map(String.init) ?? "—")
                    LabeledContent("Port interfejsu web", value: vm.status?.httpPort.map(String.init) ?? "—")
                    LabeledContent("Działa", value: vm.status?.running == true ? "Tak" : "Nie")
                    Button { Task { await vm.checkForUpdates() } } label: { Label("Sprawdź aktualizacje", systemImage: "arrow.down.circle") }
                    if let version = vm.version {
                        if version.disabled {
                            Text("Sprawdzanie aktualizacji jest wyłączone na serwerze.").font(.footnote).foregroundStyle(.secondary)
                        } else if let new = version.newVersion, !new.isEmpty {
                            Text(version.announcement ?? "Dostępna wersja \(new)").font(.footnote)
                            if version.canAutoupdate == true {
                                Button("Zaktualizuj do \(new)", role: .destructive) { confirm = .update }
                            }
                        } else {
                            Label("Masz najnowszą wersję", systemImage: "checkmark.circle").foregroundStyle(.green).font(.footnote)
                        }
                    }
                } header: {
                    Text("Serwer")
                } footer: {
                    UnavailableNote(text: "Nazwa hosta, port interfejsu web i restart usługi nie są dostępne w API AdGuard Home po instalacji – zmień je w AdGuardHome.yaml lub przez SSH (sudo systemctl restart AdGuardHome).")
                }

                Section("Profil panelu") {
                    Picker("Język", selection: $profile.language) {
                        ForEach(Self.languages, id: \.self) { Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0) }
                    }
                    Picker("Motyw panelu", selection: $profile.theme) {
                        Text("Auto").tag("auto"); Text("Ciemny").tag("dark"); Text("Jasny").tag("light")
                    }
                    Button("Zapisz profil panelu") { saveConfirm = .profile }.disabled(profile == vm.profile)
                }

                Section("Statystyki") {
                    Toggle("Zbieraj statystyki", isOn: $stats.enabled)
                    Picker("Przechowuj przez", selection: Binding(get: { stats.days }, set: { stats.interval = Double($0) * 86_400_000 })) {
                        ForEach(StatsConfig.intervalDays, id: \.self) { Text($0 == 1 ? "24 godziny" : "\($0) dni").tag($0) }
                    }
                    TextField("Ignorowane domeny (po przecinku)", text: $ignoredStats)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Zapisz ustawienia statystyk") { saveConfirm = .stats }.disabled(!statsDirty)
                    Button("Wyczyść statystyki", role: .destructive) { confirm = .stats }
                }

                Section("Query log") {
                    Toggle("Zapisuj query log", isOn: $queryLog.enabled)
                    Picker("Przechowuj przez", selection: Binding(get: { queryLog.days }, set: { queryLog.interval = $0 * 86_400_000 })) {
                        Text("6 godzin").tag(0.25); Text("24 godziny").tag(1.0); Text("7 dni").tag(7.0)
                        Text("30 dni").tag(30.0); Text("90 dni").tag(90.0)
                    }
                    Toggle("Anonimizuj adresy IP klientów", isOn: $queryLog.anonymizeClientIp)
                    TextField("Ignorowane domeny (po przecinku)", text: $ignoredLog)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Zapisz ustawienia query log") { saveConfirm = .log }.disabled(!logDirty)
                    Button("Wyczyść query log", role: .destructive) { confirm = .log }
                }

                Section {
                    Button("Wyczyść cache DNS", role: .destructive) { confirm = .cache }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle("Ustawienia ogólne")
        .task { vm.bind(app); await load() }
        .confirm(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                 message: confirm?.message, actionTitle: "Potwierdź", destructive: true) {
            switch confirm {
            case .stats: Task { await vm.resetStats() }
            case .log: Task { await vm.clearQueryLog() }
            case .cache: Task { await vm.clearCache() }
            case .update: Task { await vm.beginUpdate() }
            case nil: break
            }
        }
        .confirm("Zapisać zmiany?", isPresented: Binding(get: { saveConfirm != nil }, set: { if !$0 { saveConfirm = nil } }),
                 actionTitle: "Zapisz") {
            switch saveConfirm {
            case .stats:
                var new = stats
                new.ignored = Self.split(ignoredStats)
                Task { await vm.saveStats(new) }
            case .log:
                var new = queryLog
                new.ignored = Self.split(ignoredLog)
                Task { await vm.saveQueryLog(new) }
            case .profile: Task { await vm.saveProfile(profile) }
            case nil: break
            }
        }
    }

    private var statsDirty: Bool {
        guard let original = vm.statsConfig else { return false }
        var current = stats
        current.ignored = Self.split(ignoredStats)
        return current != original
    }

    private var logDirty: Bool {
        guard let original = vm.queryLogConfig else { return false }
        var current = queryLog
        current.ignored = Self.split(ignoredLog)
        return current != original
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func load() async {
        await vm.refresh()
        if let s = vm.statsConfig { stats = s; ignoredStats = s.ignored.joined(separator: ", ") }
        if let q = vm.queryLogConfig { queryLog = q; ignoredLog = q.ignored.joined(separator: ", ") }
        if let p = vm.profile { profile = p }
    }
}

// MARK: - TLS

struct TLSView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = TLSViewModel()
    @State private var confirmSave = false

    private var warnings: [String] {
        var list: [String] = []
        let tls = vm.validation ?? vm.config
        if let warning = tls.warningValidation, !warning.isEmpty { list.append(warning) }
        if tls.enabled == true {
            if tls.validCert == false { list.append("Certyfikat jest nieprawidłowy.") }
            if tls.validChain == false { list.append("Łańcuch certyfikatów nie jest zaufany (np. certyfikat samopodpisany).") }
            if tls.validKey == false { list.append("Klucz prywatny jest nieprawidłowy.") }
            if tls.validPair == false { list.append("Certyfikat i klucz prywatny do siebie nie pasują.") }
        }
        if let date = Formatting.parseDate(tls.notAfter) {
            if date < Date() { list.append("Certyfikat wygasł \(date.formatted(date: .abbreviated, time: .omitted)).") }
            else if date < Date().addingTimeInterval(30 * 86_400) { list.append("Certyfikat wygasa \(date.formatted(date: .abbreviated, time: .omitted)).") }
        }
        return list
    }

    var body: some View {
        LoadStateView(state: vm.state, retry: vm.refresh) {
            Form {
                if !warnings.isEmpty {
                    Section {
                        ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) }
                    }
                }
                Section("Status certyfikatu") {
                    LabeledContent("Podmiot", value: vm.config.subject ?? "—")
                    LabeledContent("Wystawca", value: vm.config.issuer ?? "—")
                    LabeledContent("Ważny od", value: Formatting.shortDateTime(vm.config.notBefore))
                    LabeledContent("Ważny do", value: Formatting.shortDateTime(vm.config.notAfter))
                    LabeledContent("Typ klucza", value: vm.config.keyType ?? "—")
                    if let names = vm.config.dnsNames, !names.isEmpty { LabeledContent("Nazwy DNS", value: names.joined(separator: ", ")) }
                }
                Section {
                    Toggle("Szyfrowanie włączone", isOn: Binding(get: { vm.config.enabled ?? false }, set: { vm.config.enabled = $0 }))
                    TextField("Nazwa serwera (np. dns.example.org)", text: Binding(get: { vm.config.serverName ?? "" }, set: { vm.config.serverName = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Wymuszaj przekierowanie na HTTPS", isOn: Binding(get: { vm.config.forceHttps ?? false }, set: { vm.config.forceHttps = $0 }))
                    portField("Port HTTPS", \.portHttps)
                    portField("Port DNS-over-TLS", \.portDnsOverTls)
                    portField("Port DNS-over-QUIC", \.portDnsOverQuic)
                    Toggle("Zwykły DNS (bez szyfrowania)", isOn: Binding(get: { vm.config.servePlainDns ?? true }, set: { vm.config.servePlainDns = $0 }))
                } header: { Text("Konfiguracja") } footer: {
                    Text("Uwaga: wymuszenie HTTPS lub zmiana portu może odciąć dostęp do panelu pod dotychczasowym adresem.")
                }
                Section("Certyfikat") {
                    TextField("Ścieżka do pliku certyfikatu", text: Binding(get: { vm.config.certificatePath ?? "" }, set: { vm.config.certificatePath = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Ścieżka do klucza prywatnego", text: Binding(get: { vm.config.privateKeyPath ?? "" }, set: { vm.config.privateKeyPath = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextEditor(text: $vm.certificateText).font(.system(.caption2, design: .monospaced)).frame(minHeight: 80)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Wklej łańcuch certyfikatów (PEM)") } footer: { Text("Zostanie wysłany jako Base64. Zostaw puste, aby użyć ścieżki lub zachować obecny certyfikat.") }
                Section {
                    TextEditor(text: $vm.privateKeyText).font(.system(.caption2, design: .monospaced)).frame(minHeight: 80)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Wklej klucz prywatny (PEM)") } footer: {
                    Text(vm.config.privateKeySaved == true ? "Serwer ma już zapisany klucz prywatny." : "Klucz jest wysyłany wyłącznie do Twojego serwera.")
                }
                Section {
                    Button { Task { await vm.validate() } } label: { Label("Sprawdź konfigurację", systemImage: "checkmark.seal") }
                        .disabled(vm.isBusy)
                    Button("Zapisz konfigurację") { confirmSave = true }.disabled(!vm.isDirty || vm.isBusy)
                    if vm.isDirty { Button("Cofnij zmiany", role: .cancel) { vm.discard() } }
                }
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("HTTPS / TLS")
        .task { vm.bind(app); await vm.refresh() }
        .confirm("Zapisać konfigurację TLS?", isPresented: $confirmSave,
                 message: "Serwer zastosuje zmiany natychmiast. Błędna konfiguracja może odciąć dostęp do panelu.", actionTitle: "Zapisz") {
            Task { _ = await vm.save() }
        }
    }

    private func portField(_ title: String, _ keyPath: WritableKeyPath<TlsConfig, Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: Binding(get: { vm.config[keyPath: keyPath].map(String.init) ?? "" },
                                         set: { vm.config[keyPath: keyPath] = Int($0) }))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
        }
    }
}

// MARK: - Kontrola dostępu

struct AccessView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = AccessViewModel()
    @State private var allowed = ""
    @State private var disallowed = ""
    @State private var blocked = ""
    @State private var confirmSave = false

    private var draft: AccessList {
        AccessList(allowedClients: Formatting.lines(allowed), disallowedClients: Formatting.lines(disallowed),
                   blockedHosts: Formatting.lines(blocked))
    }

    private var isDirty: Bool {
        let d = draft
        return d.allowed != vm.list.allowed || d.disallowed != vm.list.disallowed || d.blocked != vm.list.blocked
    }

    var body: some View {
        LoadStateView(state: vm.state, retry: reload) {
            Form {
                LinesEditor(title: "Dozwolone klienty", text: $allowed,
                            footer: "IP, CIDR lub ClientID. Jeśli lista nie jest pusta, DNS obsługuje wyłącznie te adresy.")
                LinesEditor(title: "Zablokowane klienty", text: $disallowed, footer: "IP, CIDR lub ClientID odrzucane przez serwer DNS.")
                LinesEditor(title: "Blokowane domeny (hosty)", text: $blocked,
                            footer: "Domeny, dla których serwer DNS nie odpowiada. Obsługuje składnię reguł, np. ||example.org^.")
                Section {
                    UnavailableNote(text: "API nie ma osobnej listy „dozwolonych domen”. Użyj reguł wyjątków @@||domena^ w sekcji Filtry → Reguły.")
                }
                Section {
                    Button("Zapisz kontrolę dostępu") { confirmSave = true }.disabled(!isDirty || vm.isBusy)
                }
            }
            .refreshable { await reload() }
        }
        .navigationTitle("Kontrola dostępu")
        .task { vm.bind(app); await reload() }
        .confirm("Zapisać kontrolę dostępu?", isPresented: $confirmSave,
                 message: "Niepoprawna lista dozwolonych klientów może zablokować także Ciebie.", actionTitle: "Zapisz") {
            Task { _ = await vm.save(draft) }
        }
    }

    private func reload() async {
        await vm.refresh()
        allowed = vm.list.allowed.joined(separator: "\n")
        disallowed = vm.list.disallowed.joined(separator: "\n")
        blocked = vm.list.blocked.joined(separator: "\n")
    }
}

// MARK: - Zakres funkcji

struct CoverageView: View {
    private let covered = [
        "Dashboard: status ochrony, statystyki, wykresy, top domeny/klienci, ostatnie zapytania",
        "Ochrona: pauza, filtrowanie, bezpieczne przeglądanie, rodzicielska (włącz/wyłącz), safe search, blokowane usługi, sprawdzanie domeny",
        "Query Log: lista, wyszukiwanie, filtr statusu, szczegóły, blokuj/zezwól/własna reguła, doczytywanie",
        "Filtry: listy blokujące i zezwalające, własne reguły, DNS rewrites",
        "Klienci: trwali i tymczasowi, edycja, tagi, upstreamy, blokowanie",
        "DNS: upstream/bootstrap/fallback, test, tryby, cache, blokowanie, EDNS, rate limit, prywatny reverse DNS",
        "DHCP: status, konfiguracja, dzierżawy, statyczne przypisania, wykrywanie serwerów",
        "TLS/HTTPS, kontrola dostępu, statystyki, query log, język i motyw panelu, aktualizacja"
    ]
    private let unavailable = [
        "Restart usługi AdGuard Home – brak endpointu w OpenAPI",
        "Zmiana nazwy hosta i portu interfejsu web – tylko kreator instalacji lub plik konfiguracyjny",
        "Ochrona DNS rebinding – brak w API",
        "Zmiana czułości kontroli rodzicielskiej – API tylko odczyt",
        "Dozwolone domeny jako osobna lista – użyj reguł @@||domena^",
        "Filtr czasu w Query Log – realizowany lokalnie na załadowanych danych",
        "Harmonogram blokowania usług – zachowywany, ale bez edytora",
        "Kreator pierwszej instalacji, logowanie cookie i profile mobileconfig – poza zakresem"
    ]

    var body: some View {
        List {
            Section("Pokryte funkcje") { ForEach(covered, id: \.self) { Label($0, systemImage: "checkmark.circle").font(.footnote) } }
            Section("Niedostępne / ograniczone") {
                ForEach(unavailable, id: \.self) { Label($0, systemImage: "minus.circle").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Zakres funkcji")
    }
}
