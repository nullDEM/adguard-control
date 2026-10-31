import SwiftUI

struct DNSView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = DNSViewModel()
    @State private var confirmSave = false
    @State private var confirmClearCache = false

    var body: some View {
        Group {
            LoadStateView(state: vm.state, retry: vm.refresh) {
                Form {
                    upstreamSection
                    testSection
                    modeSection
                    cacheSection
                    blockingSection
                    privateSection
                    ednsSection
                    rateLimitSection
                    Section {
                        UnavailableNote(text: "Ochrona przed DNS rebinding nie ma osobnego przełącznika w API AdGuard Home (v0.107) – jest dostępna tylko w pliku konfiguracyjnym.")
                    }
                    Section {
                        Button("Wyczyść pamięć podręczną DNS", role: .destructive) { confirmClearCache = true }
                    }
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("DNS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.isDirty { Button("Cofnij zmiany") { vm.discardChanges() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zapisz") { confirmSave = true }.disabled(!vm.isDirty || vm.isBusy)
                }
            }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .confirm("Zapisać ustawienia DNS?", isPresented: $confirmSave,
                     message: "Zmiana upstreamów lub bloku DNS od razu wpływa na wszystkich klientów.", actionTitle: "Zapisz") {
                Task { _ = await vm.save() }
            }
            .confirm("Wyczyścić pamięć podręczną DNS?", isPresented: $confirmClearCache, actionTitle: "Wyczyść", destructive: true) {
                Task { await vm.clearCache() }
            }
        }
    }

    // MARK: Sekcje

    private var upstreamSection: some View {
        Group {
            ListEditor(title: "Serwery upstream", items: $vm.config.upstreamDns,
                        footer: "Jeden na linię, np. https://dns.cloudflare.com/dns-query lub tls://1.1.1.1. Linie z # to komentarze.")
            ListEditor(title: "Serwery bootstrap", items: $vm.config.bootstrapDns,
                        footer: "Adresy IP używane do rozwiązania nazw upstreamów DoH/DoT.")
            ListEditor(title: "Serwery zapasowe (fallback)", items: $vm.config.fallbackDns,
                        footer: "Używane, gdy upstreamy nie odpowiadają.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await vm.testUpstreams() }
            } label: {
                HStack {
                    Label("Testuj upstreamy", systemImage: "checkmark.seal")
                    if vm.isTesting { Spacer(); ProgressView() }
                }
            }
            .disabled(vm.isTesting)
            ForEach(vm.testResults, id: \.server) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: entry.result == "OK" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.result == "OK" ? Palette.green : Palette.red)
                        Text(entry.server).font(.subheadline)
                    }
                    if entry.result != "OK" { Text(entry.result).font(.caption).foregroundStyle(Palette.red) }
                }
            }
        } footer: { Text("Test dotyczy wartości z formularza (także niezapisanych).") }
    }

    private var modeSection: some View {
        Section("Tryb zapytań upstream") {
            Picker("Tryb", selection: Binding(get: { vm.config.upstreamMode.flatMap { $0.isEmpty ? "load_balance" : $0 } ?? "load_balance" },
                                              set: { vm.config.upstreamMode = $0 })) {
                ForEach(DNSConfig.upstreamModes, id: \.value) { Text($0.title).tag($0.value) }
            }
            Stepper("Limit czasu: \(vm.config.upstreamTimeout ?? 10) s",
                    value: Binding(get: { vm.config.upstreamTimeout ?? 10 }, set: { vm.config.upstreamTimeout = $0 }), in: 1...60)
            Toggle("DNSSEC", isOn: Binding(get: { vm.config.dnssecEnabled ?? false }, set: { vm.config.dnssecEnabled = $0 }))
            Toggle("Wyłącz rozwiązywanie IPv6 (AAAA)", isOn: Binding(get: { vm.config.disableIpv6 ?? false }, set: { vm.config.disableIpv6 = $0 }))
        }
    }

    private var cacheSection: some View {
        Section("Pamięć podręczna") {
            Toggle("Włącz cache DNS", isOn: Binding(get: { vm.config.cacheEnabled ?? false }, set: {
                vm.config.cacheEnabled = $0
                if $0, (vm.config.cacheSize ?? 0) == 0 { vm.config.cacheSize = 4_194_304 }
            }))
            if vm.config.cacheEnabled == true {
                numberField("Rozmiar cache (bajty)", value: $vm.config.cacheSize)
                numberField("Minimalny TTL (s)", value: $vm.config.cacheTtlMin)
                numberField("Maksymalny TTL (s)", value: $vm.config.cacheTtlMax)
                Toggle("Optymistyczne cache", isOn: Binding(get: { vm.config.cacheOptimistic ?? false }, set: { vm.config.cacheOptimistic = $0 }))
            }
        }
    }

    private var blockingSection: some View {
        Section {
            Picker("Tryb blokowania", selection: Binding(get: { vm.config.blockingMode ?? "default" }, set: { vm.config.blockingMode = $0 })) {
                ForEach(DNSConfig.blockingModes, id: \.self) { Text(blockingTitle($0)).tag($0) }
            }
            if vm.config.blockingMode == "custom_ip" {
                TextField("Własny IPv4", text: Binding(get: { vm.config.blockingIpv4 ?? "" }, set: { vm.config.blockingIpv4 = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Własny IPv6", text: Binding(get: { vm.config.blockingIpv6 ?? "" }, set: { vm.config.blockingIpv6 = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            numberField("TTL zablokowanych odpowiedzi (s)", value: $vm.config.blockedResponseTtl)
        } header: { Text("Blokowanie") }
    }

    private func blockingTitle(_ mode: String) -> String {
        switch mode {
        case "default": return "Domyślny (0.0.0.0 / NXDOMAIN dla reguł hosts)"
        case "refused": return "REFUSED"
        case "nxdomain": return "NXDOMAIN"
        case "null_ip": return "Zerowy adres IP"
        case "custom_ip": return "Własny adres IP"
        default: return mode
        }
    }

    private var privateSection: some View {
        Group {
            Section {
                Toggle("Używaj prywatnych resolverów reverse DNS", isOn: Binding(get: { vm.config.usePrivatePtrResolvers ?? false }, set: { vm.config.usePrivatePtrResolvers = $0 }))
                Toggle("Rozwiązuj nazwy klientów (reverse DNS)", isOn: Binding(get: { vm.config.resolveClients ?? false }, set: { vm.config.resolveClients = $0 }))
            } header: { Text("Prywatny reverse DNS") }
            if vm.config.usePrivatePtrResolvers == true {
                ListEditor(title: "Lokalne resolvery PTR", items: $vm.config.localPtrUpstreams,
                            footer: vm.defaultPtrUpstreams.isEmpty ? nil : "Domyślne wykryte: \(vm.defaultPtrUpstreams.joined(separator: ", "))")
            }
        }
    }

    private var ednsSection: some View {
        Section("EDNS Client Subnet") {
            Toggle("Włącz EDNS CS", isOn: Binding(get: { vm.config.ednsCsEnabled ?? false }, set: { vm.config.ednsCsEnabled = $0 }))
            if vm.config.ednsCsEnabled == true {
                Toggle("Użyj własnego IP", isOn: Binding(get: { vm.config.ednsCsUseCustom ?? false }, set: { vm.config.ednsCsUseCustom = $0 }))
                if vm.config.ednsCsUseCustom == true {
                    TextField("Własny IP", text: Binding(get: { vm.config.ednsCsCustomIp ?? "" }, set: { vm.config.ednsCsCustomIp = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
        }
    }

    private var rateLimitSection: some View {
        Section {
            numberField("Limit zapytań na sekundę (0 = brak)", value: $vm.config.ratelimit)
            Stepper("Maska podsieci IPv4: /\(vm.config.ratelimitSubnetLenIpv4 ?? 24)",
                    value: Binding(get: { vm.config.ratelimitSubnetLenIpv4 ?? 24 }, set: { vm.config.ratelimitSubnetLenIpv4 = $0 }), in: 0...32)
            Stepper("Maska podsieci IPv6: /\(vm.config.ratelimitSubnetLenIpv6 ?? 56)",
                    value: Binding(get: { vm.config.ratelimitSubnetLenIpv6 ?? 56 }, set: { vm.config.ratelimitSubnetLenIpv6 = $0 }), in: 0...128)
        } header: { Text("Limit zapytań (rate limit)") }
    }

    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = Int($0) }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }
}
