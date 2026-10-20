import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = ProtectionViewModel()
    @State private var checkHost = ""
    @State private var checkClient = ""

    var body: some View {
        NavigationStack {
            LoadStateView(state: vm.state, retry: vm.refresh) {
                List {
                    globalSection
                    safeSearchSection
                    servicesSection
                    checkSection
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("Ochrona")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ProfileMenu() } }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
        }
    }

    private var globalSection: some View {
        Section {
            ConfirmedToggle(title: "Ochrona DNS", isOn: vm.status?.protectionEnabled ?? false,
                            message: "Wyłączenie ochrony zatrzyma filtrowanie dla wszystkich klientów.") {
                await vm.setProtection(enabled: $0)
            }
            ConfirmedToggle(title: "Filtrowanie (listy i reguły)", isOn: vm.filtering?.enabled ?? false) {
                await vm.setFiltering(enabled: $0)
            }
            ConfirmedToggle(title: "Bezpieczne przeglądanie", isOn: vm.safeBrowsing) { await vm.setSafeBrowsing($0) }
            ConfirmedToggle(title: "Kontrola rodzicielska", isOn: vm.parental?.enabled ?? false) { await vm.setParental($0) }
            if let sensitivity = vm.parental?.sensitivity, vm.parental?.enabled == true {
                LabeledContent("Czułość kontroli rodzicielskiej", value: "\(sensitivity)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Filtrowanie globalne")
        } footer: {
            UnavailableNote(text: "Czułość kontroli rodzicielskiej jest tylko do odczytu – API nie udostępnia jej zmiany.")
        }
    }

    private var safeSearchSection: some View {
        Section {
            ConfirmedToggle(title: "Bezpieczne wyszukiwanie", isOn: vm.safeSearch?.enabled ?? false) { value in
                await vm.updateSafeSearch({ $0.enabled = value },
                                          message: value ? "Bezpieczne wyszukiwanie włączone" : "Bezpieczne wyszukiwanie wyłączone")
            }
            if vm.safeSearch?.enabled == true {
                ForEach(SafeSearchConfig.engines, id: \.name) { engine in
                    ConfirmedToggle(title: engine.name, isOn: vm.safeSearch?[keyPath: engine.keyPath] ?? false) { value in
                        await vm.updateSafeSearch({ $0[keyPath: engine.keyPath] = value }, message: "\(engine.name): \(value ? "włączone" : "wyłączone")")
                    }
                    .padding(.leading, 12)
                }
            }
        } header: { Text("Bezpieczne wyszukiwanie") }
    }

    private var servicesSection: some View {
        Section {
            if vm.services.isEmpty {
                Text("Brak dostępnych usług").foregroundStyle(.secondary)
            }
            ForEach(vm.services) { service in
                ConfirmedToggle(title: service.name, isOn: vm.blocked.ids?.contains(service.id) ?? false,
                                message: "Zablokowanie usługi dotyczy klientów korzystających z ustawień globalnych.") {
                    await vm.setService(service.id, blocked: $0)
                }
            }
        } header: {
            Text("Blokowane usługi (\(vm.blocked.ids?.count ?? 0))")
        } footer: {
            UnavailableNote(text: "Harmonogram blokowania usług (przedziały godzin) zostaje bez zmian – edytuj go w panelu webowym.")
        }
    }

    private var checkSection: some View {
        Section {
            TextField("Domena, np. example.com", text: $checkHost)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("Klient (opcjonalnie: IP lub ClientID)", text: $checkClient)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button {
                Task { await vm.check(host: checkHost, client: checkClient) }
            } label: { Label("Sprawdź domenę", systemImage: "magnifyingglass") }
                .disabled(checkHost.trimmingCharacters(in: .whitespaces).isEmpty)

            if let result = vm.checkResult {
                let kind = QueryKind(reason: result.reason)
                LabeledContent("Wynik") { Text(kind.title).foregroundStyle(Theme.tint(for: kind)) }
                ForEach(result.rules ?? [], id: \.self) {
                    Text($0.text ?? "").font(.system(.footnote, design: .monospaced))
                }
                if let cname = result.cname { LabeledContent("CNAME", value: cname) }
                if let ips = result.ipAddrs, !ips.isEmpty { LabeledContent("IP", value: ips.joined(separator: ", ")) }
            }
            if let error = vm.checkError { Text(error).foregroundStyle(.red).font(.footnote) }
        } header: { Text("Sprawdź domenę") }
    }
}
