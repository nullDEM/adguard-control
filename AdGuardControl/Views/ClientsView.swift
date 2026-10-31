import SwiftUI

struct ClientsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = ClientsViewModel()
    @State private var editing: ClientEditorTarget?
    @State private var deleting: Client?
    @State private var search = ""

    private var filteredClients: [Client] {
        guard !search.isEmpty else { return vm.clients }
        return vm.clients.filter {
            $0.name.localizedCaseInsensitiveContains(search) || ($0.ids ?? []).contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var filteredAuto: [ClientAuto] {
        guard !search.isEmpty else { return vm.autoClients }
        return vm.autoClients.filter { $0.ip.localizedCaseInsensitiveContains(search) || ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            LoadStateView(state: vm.state, retry: vm.refresh) {
                List {
                    Section("Klienci trwali (\(filteredClients.count))") {
                        if filteredClients.isEmpty {
                            EmptyStateView(icon: "person.crop.circle.badge.plus", title: "Brak klientów",
                                           message: "Dodaj klienta, aby nadać mu osobne ustawienia filtrowania.")
                        }
                        ForEach(filteredClients) { client in
                            NavigationLink {
                                ClientDetailView(client: client, vm: vm) { editing = ClientEditorTarget(client: client) }
                            } label: { clientRow(client) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleting = client } label: { Label("Usuń", systemImage: "trash") }
                                Button { editing = ClientEditorTarget(client: client) } label: { Label("Edytuj", systemImage: "pencil") }
                                    .tint(Palette.blue)
                            }
                        }
                    }
                    Section("Klienci tymczasowi (\(filteredAuto.count))") {
                        ForEach(filteredAuto) { auto in
                            autoRow(auto)
                        }
                    }
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("Klienci")
            .searchable(text: $search, prompt: "Nazwa lub adres")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = ClientEditorTarget(client: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Dodaj klienta")
                }
            }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .sheet(item: $editing) { ClientEditor(target: $0, vm: vm) }
            .confirm("Usunąć klienta „\(deleting?.name ?? "")”?",
                     isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                     message: "Ustawienia klienta zostaną usunięte z AdGuard Home.", actionTitle: "Usuń", destructive: true) {
                if let client = deleting { Task { await vm.delete(client) } }
            }
        }
    }

    private func clientRow(_ client: Client) -> some View {
        HStack {
            Image(systemName: vm.isBlocked(client) ? "person.crop.circle.badge.xmark" : "person.crop.circle")
                .foregroundStyle(vm.isBlocked(client) ? Palette.red : Theme.accent)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name).font(.headline)
                Text((client.ids ?? []).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Formatting.number(vm.queries(for: client))).font(.subheadline.monospacedDigit())
                Text("zapytań").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func autoRow(_ auto: ClientAuto) -> some View {
        HStack {
            Image(systemName: "laptopcomputer.and.iphone").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(auto.name?.isEmpty == false ? auto.name! : auto.ip).font(.subheadline)
                Text("\(auto.ip)\(auto.source.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isBlocked(ip: auto.ip) { Image(systemName: "nosign").foregroundStyle(Palette.red) }
            Text(Formatting.number(vm.queryCounts[auto.ip] ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button {
                var client = Client.new()
                client.name = auto.name?.isEmpty == false ? auto.name! : auto.ip
                client.ids = [auto.ip]
                editing = ClientEditorTarget(client: nil, prefill: client)
            } label: { Label("Zapisz", systemImage: "plus") }.tint(Palette.green)
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await vm.setBlocked(ids: [auto.ip], blocked: !vm.isBlocked(ip: auto.ip), label: auto.ip) }
            } label: { Label(vm.isBlocked(ip: auto.ip) ? "Odblokuj" : "Blokuj", systemImage: "nosign") }
                .tint(vm.isBlocked(ip: auto.ip) ? Palette.green : Palette.red)
        }
    }
}

struct ClientDetailView: View {
    let client: Client
    @ObservedObject var vm: ClientsViewModel
    let edit: () -> Void
    @State private var recent: [QueryLogItem] = []

    private var current: Client { vm.clients.first { $0.name == client.name } ?? client }

    var body: some View {
        List {
            Section("Informacje") {
                LabeledContent("Identyfikatory", value: (current.ids ?? []).joined(separator: ", "))
                LabeledContent("Zapytania", value: Formatting.number(vm.queries(for: current)))
                LabeledContent("Ustawienia", value: current.useGlobalSettings == true ? "Globalne" : "Własne")
                if !(current.tags ?? []).isEmpty { LabeledContent("Tagi", value: (current.tags ?? []).joined(separator: ", ")) }
                if !(current.upstreams ?? []).isEmpty { LabeledContent("Upstream", value: (current.upstreams ?? []).joined(separator: ", ")) }
            }
            Section {
                ConfirmedToggle(title: "Zablokuj klienta", isOn: vm.isBlocked(current), confirmation: .whenTurningOn,
                                message: "Zablokowany klient nie będzie obsługiwany przez serwer DNS.") {
                    await vm.setBlocked(ids: current.ids ?? [], blocked: $0, label: current.name)
                }
            } footer: { Text("Dodaje identyfikatory klienta do listy zablokowanych klientów (kontrola dostępu).") }
            Section("Ostatnie zapytania") {
                if recent.isEmpty { Text("Brak zapytań").foregroundStyle(.secondary) }
                ForEach(recent) { QueryRow(item: $0) }
            }
        }
        .navigationTitle(current.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edytuj", action: edit) } }
        .task { recent = await vm.recentQueries(for: current.ids ?? []) }
    }
}

struct ClientEditorTarget: Identifiable {
    let id = UUID()
    let client: Client?
    var prefill: Client?
}

private struct ClientEditor: View {
    let target: ClientEditorTarget
    @ObservedObject var vm: ClientsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Client.new()
    @State private var idsText = ""
    @State private var upstreamsText = ""
    @State private var confirmSave = false
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { target.client == nil }
    private var idsError: String? { Validators.clientIDsError(Formatting.lines(idsText)) }
    private var nameError: String? {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let taken = vm.clients.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.name != target.client?.name }
        return taken ? "Klient o takiej nazwie już istnieje." : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Klient") {
                    TextField("Nazwa", text: $draft.name).focused($nameFocused)
                    FieldError(message: nameError)
                }
                LinesEditor(title: "Identyfikatory", text: $idsText, footer: "IP, CIDR, adres MAC lub ClientID – jeden na linię.")
                if let idsError { Section { FieldError(message: idsError) } }
                Section("Filtrowanie") {
                    Toggle("Użyj ustawień globalnych", isOn: Binding(get: { draft.useGlobalSettings ?? true }, set: { draft.useGlobalSettings = $0 }))
                    if draft.useGlobalSettings == false {
                        Toggle("Filtrowanie", isOn: Binding(get: { draft.filteringEnabled ?? false }, set: { draft.filteringEnabled = $0 }))
                        Toggle("Bezpieczne przeglądanie", isOn: Binding(get: { draft.safebrowsingEnabled ?? false }, set: { draft.safebrowsingEnabled = $0 }))
                        Toggle("Kontrola rodzicielska", isOn: Binding(get: { draft.parentalEnabled ?? false }, set: { draft.parentalEnabled = $0 }))
                        Toggle("Bezpieczne wyszukiwanie", isOn: Binding(get: { draft.safeSearch?.enabled ?? false }, set: {
                            var config = draft.safeSearch ?? SafeSearchConfig()
                            config.enabled = $0
                            if $0 { SafeSearchConfig.engines.forEach { config[keyPath: $0.keyPath] = config[keyPath: $0.keyPath] ?? true } }
                            draft.safeSearch = config
                        }))
                    }
                }
                Section("Blokowane usługi") {
                    Toggle("Użyj globalnych blokad usług", isOn: Binding(get: { draft.useGlobalBlockedServices ?? true }, set: { draft.useGlobalBlockedServices = $0 }))
                    if draft.useGlobalBlockedServices == false {
                        NavigationLink("Wybrane usługi: \(draft.blockedServices?.count ?? 0)") {
                            ServicePicker(services: vm.availableServices,
                                          selection: Binding(get: { Set(draft.blockedServices ?? []) }, set: { draft.blockedServices = $0.sorted() }))
                        }
                    }
                }
                LinesEditor(title: "Dedykowane upstream DNS", text: $upstreamsText,
                            footer: "Puste = upstreamy globalne. Np. 1.1.1.1 lub [/lan/]192.168.1.1")
                if !vm.supportedTags.isEmpty {
                    Section("Tagi") {
                        ForEach(vm.supportedTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(
                                get: { draft.tags?.contains(tag) ?? false },
                                set: { on in
                                    var tags = Set(draft.tags ?? [])
                                    if on { tags.insert(tag) } else { tags.remove(tag) }
                                    draft.tags = tags.sorted()
                                }))
                        }
                    }
                }
                Section("Prywatność") {
                    Toggle("Nie zapisuj w query log", isOn: Binding(get: { draft.ignoreQuerylog ?? false }, set: { draft.ignoreQuerylog = $0 }))
                    Toggle("Nie licz w statystykach", isOn: Binding(get: { draft.ignoreStatistics ?? false }, set: { draft.ignoreStatistics = $0 }))
                }
            }
            .navigationTitle(isNew ? "Nowy klient" : "Edytuj klienta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { confirmSave = true }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || Formatting.lines(idsText).isEmpty
                                  || idsError != nil || nameError != nil)
                }
            }
            .confirm(isNew ? "Dodać klienta?" : "Zapisać zmiany klienta?", isPresented: $confirmSave,
                     message: draft.name, actionTitle: "Zapisz") {
                var client = draft
                client.name = client.name.trimmingCharacters(in: .whitespaces)
                client.ids = Formatting.lines(idsText)
                client.upstreams = Formatting.lines(upstreamsText)
                Task { if await vm.save(client, replacing: target.client?.name) { dismiss() } }
            }
            .task { await vm.loadServicesIfNeeded() }
            .onAppear {
                draft = target.client ?? target.prefill ?? Client.new()
                idsText = (draft.ids ?? []).joined(separator: "\n")
                upstreamsText = (draft.upstreams ?? []).joined(separator: "\n")
                if isNew && target.prefill == nil { nameFocused = true }
            }
        }
    }
}

private struct ServicePicker: View {
    let services: [BlockedService]
    @Binding var selection: Set<String>

    var body: some View {
        List(services.sorted { $0.name < $1.name }) { service in
            Button {
                if selection.contains(service.id) { selection.remove(service.id) } else { selection.insert(service.id) }
            } label: {
                HStack {
                    Text(service.name).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(service.id) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
        }
        .navigationTitle("Blokowane usługi")
    }
}
