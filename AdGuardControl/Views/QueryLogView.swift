import SwiftUI

struct QueryLogView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = QueryLogViewModel()
    @State private var showFilters = false
    @State private var pendingQuickAction: QuickAction?

    /// Szybka akcja z przeciągnięcia wiersza – wymaga potwierdzenia, bo zmienia reguły filtrowania.
    struct QuickAction: Identifiable {
        enum Kind { case block, allow }
        let kind: Kind
        let domain: String
        var id: String { "\(kind)-\(domain)" }
    }

    var body: some View {
        NavigationStack {
            LoadStateView(state: vm.state, retry: vm.reload) {
                List {
                    if vm.visibleItems.isEmpty {
                        EmptyStateView(icon: "list.bullet.rectangle", title: "Brak zapytań",
                                       message: vm.hasActiveFilters ? "Zmień lub wyczyść filtry." : "Query log jest pusty albo wyłączony.")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(vm.visibleItems) { item in
                        NavigationLink {
                            QueryDetailView(item: item, vm: vm)
                        } label: {
                            QueryRow(item: item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { pendingQuickAction = QuickAction(kind: .block, domain: item.domain) } label: { Label("Blokuj", systemImage: "hand.raised") }
                                .tint(.red)
                            Button { pendingQuickAction = QuickAction(kind: .allow, domain: item.domain) } label: { Label("Zezwól", systemImage: "checkmark.shield") }
                                .tint(.green)
                        }
                        .onAppear {
                            if item.id == vm.items.last?.id { Task { await vm.loadMore() } }
                        }
                    }
                    if vm.isLoadingMore {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.reload() }
                .animation(.default, value: vm.visibleItems.count)
            }
            .navigationTitle("Query Log")
            .searchable(text: $vm.search, prompt: "Domena lub IP klienta")
            .onSubmit(of: .search) { Task { await vm.submitSearch() } }
            .onChange(of: vm.search) { _, _ in vm.searchTextChanged() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: vm.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filtry")
                }
            }
            .sheet(isPresented: $showFilters) { filterSheet }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .confirm(pendingQuickAction.map { $0.kind == .block ? "Zablokować \($0.domain)?" : "Dodać \($0.domain) do białej listy?" } ?? "",
                     isPresented: Binding(get: { pendingQuickAction != nil }, set: { if !$0 { pendingQuickAction = nil } }),
                     message: pendingQuickAction.map {
                         "Zostanie dodana reguła \($0.kind == .block ? UserRule.blockRule(domain: $0.domain) : UserRule.allowRule(domain: $0.domain))."
                     },
                     actionTitle: pendingQuickAction?.kind == .block ? "Zablokuj" : "Dodaj") {
                guard let action = pendingQuickAction else { return }
                Task {
                    if action.kind == .block { await vm.blockDomain(action.domain) } else { await vm.allowDomain(action.domain) }
                }
            }
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $vm.statusFilter) {
                        ForEach(QueryStatusFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Klient (IP, nazwa, ClientID)", text: $vm.clientFilter)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Klient") } footer: { Text("Filtr stosowany do załadowanych zapytań.") }
                Section {
                    Picker("Czas", selection: $vm.timeRange) {
                        ForEach(QueryTimeRange.allCases) { Text($0.title).tag($0) }
                    }
                } header: { Text("Czas") } footer: { Text("API AdGuard Home nie ma filtra czasu – zakres jest stosowany lokalnie.") }
                Section {
                    Button("Wyczyść filtry", role: .destructive) { vm.resetFilters(); Task { await vm.reload() } }
                }
            }
            .navigationTitle("Filtry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zastosuj") { showFilters = false; Task { await vm.reload() } }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct QueryDetailView: View {
    let item: QueryLogItem
    @ObservedObject var vm: QueryLogViewModel

    @State private var pending: PendingAction?
    @State private var customRule = ""
    @State private var showCustomRule = false

    enum PendingAction: Identifiable {
        case block, allow
        var id: Int { self == .block ? 0 : 1 }
    }

    var body: some View {
        List {
            Section("Zapytanie") {
                row("Domena", item.question?.unicodeName ?? item.domain)
                row("Typ", item.question?.type)
                row("Czas", Formatting.shortDateTime(item.time))
                row("Status DNS", item.status)
                HStack {
                    Text("Wynik filtrowania")
                    Spacer()
                    Text(item.kind.title).foregroundStyle(Theme.tint(for: item.kind))
                }
                if let service = item.serviceName { row("Usługa", service) }
            }
            Section("Klient") {
                row("Adres", item.client)
                row("Nazwa", item.clientInfo?.name)
                row("ClientID", item.clientId)
                row("Protokół", item.clientProto?.isEmpty == false ? item.clientProto : "DNS")
                row("ECS", item.ecs)
            }
            Section("Odpowiedź") {
                row("Upstream", item.upstream)
                row("Czas przetwarzania", item.elapsedMs.map { "\($0) ms" })
                row("Z cache", item.cached == true ? "Tak" : "Nie")
                row("DNSSEC", item.answerDnssec == true ? "Zweryfikowane" : "—")
                ForEach(item.answer ?? [], id: \.self) { answer in
                    LabeledContent(answer.type ?? "", value: answer.value ?? "")
                        .font(.footnote)
                }
            }
            if let rules = item.rules, !rules.isEmpty {
                Section("Zastosowane reguły") {
                    ForEach(rules, id: \.self) { Text($0.text ?? "").font(.system(.footnote, design: .monospaced)) }
                }
            }
            Section("Szybkie akcje") {
                Button { pending = .block } label: { Label("Zablokuj domenę", systemImage: "hand.raised") }
                    .tint(.red)
                Button { pending = .allow } label: { Label("Dodaj do białej listy", systemImage: "checkmark.shield") }
                    .tint(.green)
                Button {
                    customRule = UserRule.blockRule(domain: item.domain)
                    showCustomRule = true
                } label: { Label("Dodaj własną regułę…", systemImage: "plus.square.on.square") }
            }
        }
        .navigationTitle(item.domain)
        .navigationBarTitleDisplayMode(.inline)
        .confirm(pending == .block ? "Zablokować \(item.domain)?" : "Dodać \(item.domain) do białej listy?",
                 isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                 message: pending == .block ? "Zostanie dodana reguła \(UserRule.blockRule(domain: item.domain))."
                                            : "Zostanie dodana reguła \(UserRule.allowRule(domain: item.domain)).",
                 actionTitle: pending == .block ? "Zablokuj" : "Dodaj") {
            let action = pending
            Task {
                if action == .block { await vm.blockDomain(item.domain) } else { await vm.allowDomain(item.domain) }
            }
        }
        .alert("Własna reguła filtrowania", isPresented: $showCustomRule) {
            TextField("Reguła", text: $customRule)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Dodaj") { let rule = customRule; Task { await vm.addUserRule(rule) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Np. ||domena^ blokuje, @@||domena^ zezwala.")
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }
}
