import SwiftUI

struct DHCPView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = DHCPViewModel()
    @State private var confirmSave = false
    @State private var confirmResetLeases = false
    @State private var confirmResetAll = false
    @State private var editingStatic: StaticLeaseTarget?
    @State private var deleting: DhcpStaticLease?
    @State private var makingStatic: DhcpLease?

    var body: some View {
        Group {
            Group {
                if let message = vm.unavailableMessage {
                    ScrollView {
                        EmptyStateView(icon: "network.slash", title: "DHCP niedostępny",
                                       message: message.isEmpty ? "Serwer DHCP nie jest obsługiwany w tym środowisku." : message)
                            .padding()
                    }
                } else {
                    LoadStateView(state: vm.state, retry: vm.refresh) { content }
                }
            }
            .navigationTitle("DHCP")
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .sheet(item: $editingStatic) { StaticLeaseEditor(target: $0, vm: vm) }
            .confirm("Zapisać konfigurację DHCP?", isPresented: $confirmSave,
                     message: "Błędny zakres lub brama mogą zakłócić działanie sieci.", actionTitle: "Zapisz") {
                Task { _ = await vm.save() }
            }
            .confirm("Wyczyścić wszystkie dzierżawy?", isPresented: $confirmResetLeases,
                     message: "Klienci otrzymają nowe adresy przy kolejnym odnowieniu.", actionTitle: "Wyczyść", destructive: true) {
                Task { await vm.resetLeases() }
            }
            .confirm("Zresetować konfigurację DHCP?", isPresented: $confirmResetAll,
                     message: "Przywróci ustawienia domyślne i usunie dzierżawy.", actionTitle: "Resetuj", destructive: true) {
                Task { await vm.resetAll() }
            }
            .confirm("Przypisać adres na stałe?", isPresented: Binding(get: { makingStatic != nil }, set: { if !$0 { makingStatic = nil } }),
                     message: makingStatic.map { "\($0.hostname.isEmpty ? $0.mac : $0.hostname) zawsze dostanie adres \($0.ip)." },
                     actionTitle: "Przypisz") {
                if let lease = makingStatic { Task { await vm.makeStatic(from: lease) } }
            }
            .confirm("Usunąć dzierżawę statyczną?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                     message: deleting.map { "\($0.hostname) – \($0.ip)" }, actionTitle: "Usuń", destructive: true) {
                if let lease = deleting { Task { await vm.removeStatic(lease) } }
            }
        }
    }

    private var content: some View {
        List {
            Section {
                ConfirmedToggle(title: "Serwer DHCP", isOn: vm.status?.enabled ?? false, confirmation: .whenTurningOff,
                                message: "Włączenie DHCP, gdy w sieci działa inny serwer DHCP, spowoduje konflikty adresów.") {
                    await vm.setEnabled($0)
                }
                Picker("Interfejs", selection: $vm.draft.interfaceName) {
                    if vm.draft.interfaceName.isEmpty { Text("—").tag("") }
                    ForEach(vm.interfaces.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                Button {
                    Task { await vm.findActiveServers() }
                } label: { Label("Szukaj innych serwerów DHCP", systemImage: "dot.radiowaves.left.and.right") }
                    .disabled(vm.draft.interfaceName.isEmpty || vm.isBusy)
                if let result = vm.searchResult { searchSummary(result) }
            } header: { Text("Status") }

            Section("Zakres IPv4") {
                field("Brama", \.gatewayIp)
                field("Maska podsieci", \.subnetMask)
                field("Początek zakresu", \.rangeStart)
                field("Koniec zakresu", \.rangeEnd)
                HStack {
                    Text("Czas dzierżawy (s)")
                    Spacer()
                    TextField("86400", text: Binding(
                        get: { String(vm.draft.v4?.leaseDuration ?? 86400) },
                        set: { ensureV4(); vm.draft.v4?.leaseDuration = Int($0) ?? 0 }))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                }
            }
            Section {
                if v4Invalid {
                    FieldError(message: "Popraw adresy IPv4 zaznaczone na czerwono.")
                }
                Button("Zapisz konfigurację") { confirmSave = true }.disabled(!vm.isDirty || vm.isBusy || v4Invalid)
            }

            Section("Statyczne dzierżawy (\(vm.staticLeases.count))") {
                if vm.staticLeases.isEmpty { Text("Brak przypisań").foregroundStyle(.secondary) }
                ForEach(vm.staticLeases) { lease in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lease.hostname.isEmpty ? lease.mac : lease.hostname).font(.headline)
                        Text("\(lease.ip) · \(lease.mac)").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = lease } label: { Label("Usuń", systemImage: "trash") }
                        Button { editingStatic = StaticLeaseTarget(lease: lease) } label: { Label("Edytuj", systemImage: "pencil") }.tint(Palette.blue)
                    }
                }
                Button { editingStatic = StaticLeaseTarget(lease: nil) } label: { Label("Dodaj przypisanie", systemImage: "plus") }
            }

            Section("Aktywne dzierżawy (\(vm.leases.count))") {
                if vm.leases.isEmpty { Text("Brak aktywnych dzierżaw").foregroundStyle(.secondary) }
                ForEach(vm.leases) { lease in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lease.hostname.isEmpty ? lease.mac : lease.hostname).font(.subheadline.weight(.medium))
                        Text("\(lease.ip) · \(lease.mac)").font(.caption).foregroundStyle(.secondary)
                        Text("Wygasa: \(Formatting.shortDateTime(lease.expires))").font(.caption2).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button { makingStatic = lease } label: { Label("Statyczny", systemImage: "pin") }.tint(Palette.green)
                    }
                }
            }

            Section {
                Button("Wyczyść dzierżawy", role: .destructive) { confirmResetLeases = true }
                Button("Resetuj konfigurację DHCP", role: .destructive) { confirmResetAll = true }
            }
        }
        .refreshable { await vm.refresh() }
    }

    private func ensureV4() {
        if vm.draft.v4 == nil {
            vm.draft.v4 = DhcpConfigV4(gatewayIp: "", subnetMask: "255.255.255.0", rangeStart: "", rangeEnd: "", leaseDuration: 86400)
        }
    }

    private func field(_ title: String, _ keyPath: WritableKeyPath<DhcpConfigV4, String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0.0.0.0", text: Binding(
                get: { vm.draft.v4?[keyPath: keyPath] ?? "" },
                set: { ensureV4(); vm.draft.v4?[keyPath: keyPath] = $0 }))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing).frame(maxWidth: 180)
                .foregroundStyle(addressIsValid(vm.draft.v4?[keyPath: keyPath] ?? "") ? Color.primary : Palette.red)
        }
        .accessibilityElement(children: .combine)
    }

    /// Puste pole nie jest jeszcze błędem; wypełnione musi być poprawnym adresem IPv4.
    private func addressIsValid(_ text: String) -> Bool { text.isEmpty || Validators.isIPv4(text.trimmingCharacters(in: .whitespaces)) }

    private var v4Invalid: Bool {
        guard let v4 = vm.draft.v4 else { return false }
        return ![v4.gatewayIp, v4.subnetMask, v4.rangeStart, v4.rangeEnd].allSatisfy(addressIsValid)
    }

    @ViewBuilder
    private func searchSummary(_ result: DhcpSearchResult) -> some View {
        let v4 = result.v4?.otherServer?.found ?? "no"
        let v6 = result.v6?.otherServer?.found ?? "no"
        Label("Inny serwer DHCP IPv4: \(v4 == "yes" ? "wykryty" : v4 == "error" ? "błąd" : "nie wykryto")",
              systemImage: v4 == "yes" ? "exclamationmark.triangle.fill" : "checkmark.circle")
            .foregroundStyle(v4 == "yes" ? Palette.orange : .secondary).font(.footnote)
        Label("Inny serwer DHCP IPv6: \(v6 == "yes" ? "wykryty" : v6 == "error" ? "błąd" : "nie wykryto")",
              systemImage: v6 == "yes" ? "exclamationmark.triangle.fill" : "checkmark.circle")
            .foregroundStyle(v6 == "yes" ? Palette.orange : .secondary).font(.footnote)
        if result.v4?.staticIp?.static == "no", let ip = result.v4?.staticIp?.ip, !ip.isEmpty {
            Label("Interfejs ma dynamiczny adres IP (\(ip)). Ustaw statyczny przed włączeniem DHCP.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.orange).font(.footnote)
        }
    }
}

struct StaticLeaseTarget: Identifiable {
    let id = UUID()
    let lease: DhcpStaticLease?
}

private struct StaticLeaseEditor: View {
    let target: StaticLeaseTarget
    @ObservedObject var vm: DHCPViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mac = ""
    @State private var ip = ""
    @State private var hostname = ""
    @State private var confirmSave = false
    @FocusState private var focus: Field?

    private enum Field { case mac, ip, hostname }
    private var macError: String? { Validators.macError(mac) }
    private var ipError: String? { Validators.ipError(ip) }
    private var hostnameError: String? { Validators.hostnameError(hostname) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Adres MAC (aa:bb:cc:dd:ee:ff)", text: $mac)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(target.lease != nil)
                        .focused($focus, equals: .mac).submitLabel(.next).onSubmit { focus = .ip }
                    FieldError(message: macError)
                    TextField("Adres IP", text: $ip).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focus, equals: .ip).submitLabel(.next).onSubmit { focus = .hostname }
                    FieldError(message: ipError)
                    TextField("Nazwa hosta", text: $hostname).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .hostname).submitLabel(.done)
                    FieldError(message: hostnameError)
                }
            }
            .navigationTitle(target.lease == nil ? "Nowe przypisanie" : "Edytuj przypisanie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { confirmSave = true }
                        .disabled(mac.isEmpty || ip.isEmpty || macError != nil || ipError != nil || hostnameError != nil)
                }
            }
            .confirm("Zapisać przypisanie?", isPresented: $confirmSave, message: "\(mac) → \(ip)", actionTitle: "Zapisz") {
                let lease = DhcpStaticLease(mac: mac.trimmingCharacters(in: .whitespaces), ip: ip.trimmingCharacters(in: .whitespaces),
                                            hostname: hostname.trimmingCharacters(in: .whitespaces))
                Task {
                    let ok: Bool
                    if let previous = target.lease { ok = await vm.updateStatic(lease, previous: previous) } else { ok = await vm.addStatic(lease) }
                    if ok { dismiss() }
                }
            }
            .onAppear {
                mac = target.lease?.mac ?? ""
                ip = target.lease?.ip ?? ""
                hostname = target.lease?.hostname ?? ""
                if target.lease == nil { focus = .mac }
            }
        }
        .presentationDetents([.medium])
    }
}
