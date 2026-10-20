import SwiftUI

struct FiltersView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case blocklists = "Blokujące", allowlists = "Zezwalające", rules = "Reguły", rewrites = "Rewrites"
        var id: String { rawValue }
    }

    @EnvironmentObject private var app: AppState
    @StateObject private var vm = FiltersViewModel()
    @State private var tab: Tab = .blocklists
    @State private var editingFilter: FilterEditorTarget?
    @State private var editingRule: RuleEditorTarget?
    @State private var editingRewrite: RewriteEditorTarget?
    @State private var showRawEditor = false
    @State private var pendingInterval: Int?

    var body: some View {
        NavigationStack {
            LoadStateView(state: vm.state, retry: vm.refresh) {
                VStack(spacing: 0) {
                    Picker("Sekcja", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)

                    List {
                        switch tab {
                        case .blocklists: filterList(vm.blocklists, whitelist: false)
                        case .allowlists: filterList(vm.allowlists, whitelist: true)
                        case .rules: rulesList
                        case .rewrites: rewritesList
                        }
                    }
                    .refreshable { await vm.refresh() }
                }
            }
            .navigationTitle("Filtry")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addTapped() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Dodaj")
                }
            }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .sheet(item: $editingFilter) { FilterEditor(target: $0, vm: vm) }
            .sheet(item: $editingRule) { RuleEditor(target: $0, vm: vm) }
            .sheet(item: $editingRewrite) { RewriteEditor(target: $0, vm: vm) }
            .sheet(isPresented: $showRawEditor) { RawRulesEditor(vm: vm) }
            .confirm("Zmienić częstotliwość aktualizacji?", isPresented: Binding(get: { pendingInterval != nil }, set: { if !$0 { pendingInterval = nil } }),
                     message: "Listy filtrów będą pobierane z nową częstotliwością.", actionTitle: "Zmień") {
                if let hours = pendingInterval { Task { await vm.setInterval(hours) } }
            }
        }
    }

    private func addTapped() {
        switch tab {
        case .blocklists: editingFilter = FilterEditorTarget(filter: nil, whitelist: false)
        case .allowlists: editingFilter = FilterEditorTarget(filter: nil, whitelist: true)
        case .rules: editingRule = RuleEditorTarget(rule: nil)
        case .rewrites: editingRewrite = RewriteEditorTarget(entry: nil)
        }
    }

    // MARK: Listy filtrów

    @ViewBuilder
    private func filterList(_ filters: [Filter], whitelist: Bool) -> some View {
        Section {
            if !whitelist {
                ConfirmedToggle(title: "Filtrowanie włączone", isOn: vm.status?.enabled ?? false) { await vm.setFilteringEnabled($0) }
                Picker("Aktualizuj co", selection: Binding(get: { vm.status?.interval ?? 24 }, set: { pendingInterval = $0 })) {
                    Text("Nigdy").tag(0)
                    Text("1 godz.").tag(1)
                    Text("12 godz.").tag(12)
                    Text("1 dzień").tag(24)
                    Text("3 dni").tag(72)
                    Text("7 dni").tag(168)
                }
            }
            Button { Task { await vm.refreshFilters(whitelist: whitelist) } } label: {
                Label("Sprawdź aktualizacje list", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.isBusy)
        }
        Section(whitelist ? "Listy zezwalające" : "Listy blokujące") {
            if filters.isEmpty {
                EmptyStateView(icon: "tray", title: "Brak list", message: "Dodaj listę przyciskiem +.")
            }
            ForEach(filters) { filter in
                FilterRow(filter: filter, whitelist: whitelist, vm: vm) {
                    editingFilter = FilterEditorTarget(filter: filter, whitelist: whitelist)
                }
            }
        }
    }

    // MARK: Własne reguły

    @ViewBuilder
    private var rulesList: some View {
        Section {
            Button { showRawEditor = true } label: { Label("Edytuj wszystkie reguły jako tekst", systemImage: "doc.plaintext") }
        } footer: {
            Text("Składnia: ||domena^ blokuje, @@||domena^ zezwala, # lub ! to komentarz. Wyłączona reguła to reguła zakomentowana (! ||domena^).")
        }
        Section("Własne reguły (\(vm.userRules.count))") {
            if vm.userRules.isEmpty {
                EmptyStateView(icon: "text.badge.plus", title: "Brak własnych reguł")
            }
            ForEach(vm.userRules) { rule in
                RuleRow(rule: rule, vm: vm) { editingRule = RuleEditorTarget(rule: rule) }
            }
        }
    }

    // MARK: Rewrites

    @ViewBuilder
    private var rewritesList: some View {
        Section {
            ConfirmedToggle(title: "Przepisywanie DNS", isOn: vm.rewritesEnabled) { await vm.setRewritesEnabled($0) }
        }
        Section("Przepisania (\(vm.rewrites.count))") {
            if vm.rewrites.isEmpty {
                EmptyStateView(icon: "arrow.triangle.swap", title: "Brak przepisań",
                               message: "Np. nas.home → 192.168.1.20 albo alias → inna-domena.")
            }
            ForEach(vm.rewrites) { entry in
                RewriteRow(entry: entry, vm: vm) { editingRewrite = RewriteEditorTarget(entry: entry) }
            }
        }
    }
}

// MARK: - Wiersze

private struct FilterRow: View {
    let filter: Filter
    let whitelist: Bool
    @ObservedObject var vm: FiltersViewModel
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ConfirmedToggle(title: filter.name, isOn: filter.enabled) { await vm.setFilter(filter, enabled: $0, whitelist: whitelist) }
            Text(filter.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Label("\(Formatting.number(filter.rulesCount)) reguł", systemImage: "list.number")
                Spacer()
                Text("Aktualizacja: \(Formatting.shortDateTime(filter.lastUpdated))")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Usuń", systemImage: "trash") }
            Button(action: edit) { Label("Edytuj", systemImage: "pencil") }.tint(.blue)
        }
        .confirm("Usunąć listę „\(filter.name)”?", isPresented: $confirmDelete,
                 message: "Lista zostanie usunięta z AdGuard Home.", actionTitle: "Usuń", destructive: true) {
            Task { await vm.removeFilter(filter, whitelist: whitelist) }
        }
    }
}

private struct RuleRow: View {
    let rule: UserRule
    @ObservedObject var vm: FiltersViewModel
    let edit: () -> Void
    @State private var confirmDelete = false
    @State private var confirmToggle = false

    private var icon: (String, Color) {
        switch rule.kind {
        case .block: return ("hand.raised.fill", .red)
        case .allow: return ("checkmark.shield.fill", .green)
        case .comment: return ("text.quote", .secondary)
        case .disabled: return ("pause.circle", .orange)
        case .other: return ("questionmark.circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.0).foregroundStyle(icon.1)
            Text(rule.text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Usuń", systemImage: "trash") }
            if rule.kind != .comment {
                Button { confirmToggle = true } label: {
                    Label(rule.isEnabled ? "Wyłącz" : "Włącz", systemImage: rule.isEnabled ? "pause" : "play")
                }.tint(.orange)
            }
        }
        .confirm("Usunąć regułę?", isPresented: $confirmDelete, message: rule.text, actionTitle: "Usuń", destructive: true) {
            Task { await vm.deleteRule(rule) }
        }
        .confirm(rule.isEnabled ? "Wyłączyć regułę?" : "Włączyć regułę?", isPresented: $confirmToggle, message: rule.text) {
            Task { await vm.toggleRule(rule) }
        }
    }
}

private struct RewriteRow: View {
    let entry: RewriteEntry
    @ObservedObject var vm: FiltersViewModel
    let edit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ConfirmedToggle(title: entry.domain, isOn: entry.enabled ?? true) {
                _ = await vm.updateRewrite(entry, domain: entry.domain, answer: entry.answer, enabled: $0)
            }
            Label(entry.answer, systemImage: "arrow.right").font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Usuń", systemImage: "trash") }
            Button(action: edit) { Label("Edytuj", systemImage: "pencil") }.tint(.blue)
        }
        .confirm("Usunąć przepisanie \(entry.domain)?", isPresented: $confirmDelete, actionTitle: "Usuń", destructive: true) {
            Task { await vm.deleteRewrite(entry) }
        }
    }
}

// MARK: - Edytory

struct FilterEditorTarget: Identifiable {
    let id = UUID()
    let filter: Filter?
    let whitelist: Bool
}

private struct FilterEditor: View {
    let target: FilterEditorTarget
    @ObservedObject var vm: FiltersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var enabled = true
    @State private var confirmSave = false
    @FocusState private var focus: Field?

    private enum Field { case name, url }
    private var urlError: String? { Validators.filterURLError(url) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nazwa", text: $name)
                        .focused($focus, equals: .name).submitLabel(.next).onSubmit { focus = .url }
                    TextField("Adres URL lub ścieżka pliku", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($focus, equals: .url).submitLabel(.done)
                    FieldError(message: urlError)
                    if target.filter != nil { Toggle("Włączona", isOn: $enabled) }
                } footer: {
                    Text("Np. https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt")
                }
            }
            .navigationTitle(target.filter == nil ? "Nowa lista" : "Edytuj listę")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { confirmSave = true }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty
                                  || urlError != nil)
                }
            }
            .confirm(target.filter == nil ? "Dodać listę?" : "Zapisać zmiany?", isPresented: $confirmSave,
                     message: url, actionTitle: "Zapisz") {
                Task {
                    let ok: Bool
                    if let filter = target.filter {
                        ok = await vm.updateFilter(filter, name: name, url: url, enabled: enabled, whitelist: target.whitelist)
                    } else {
                        ok = await vm.addFilter(name: name, url: url, whitelist: target.whitelist)
                    }
                    if ok { dismiss() }
                }
            }
            .onAppear {
                name = target.filter?.name ?? ""
                url = target.filter?.url ?? ""
                enabled = target.filter?.enabled ?? true
                if target.filter == nil { focus = .name }
            }
        }
        .presentationDetents([.medium])
    }
}

struct RuleEditorTarget: Identifiable {
    let id = UUID()
    let rule: UserRule?
}

private struct RuleEditor: View {
    let target: RuleEditorTarget
    @ObservedObject var vm: FiltersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmSave = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("||domena^", text: $text, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused)
                } footer: {
                    Text("Przykłady: ||ads.example.com^ (blokada), @@||example.com^ (wyjątek), # komentarz")
                }
                Section("Szablony") {
                    Button("Blokuj domenę (||domena^)") { text = "||^" }
                    Button("Zezwól na domenę (@@||domena^)") { text = "@@||^" }
                    Button("Komentarz (# …)") { text = "# " }
                }
            }
            .navigationTitle(target.rule == nil ? "Nowa reguła" : "Edytuj regułę")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { confirmSave = true }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirm("Zapisać regułę?", isPresented: $confirmSave, message: text, actionTitle: "Zapisz") {
                Task {
                    let ok: Bool
                    if let rule = target.rule { ok = await vm.editRule(rule, to: text) } else { ok = await vm.addRule(text) }
                    if ok { dismiss() }
                }
            }
            .onAppear { text = target.rule?.text ?? ""; focused = true }
        }
        .presentationDetents([.medium])
    }
}

private struct RawRulesEditor: View {
    @ObservedObject var vm: FiltersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmSave = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(8)
                .navigationTitle("Własne reguły")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Zapisz") { confirmSave = true } }
                }
                .confirm("Zastąpić wszystkie własne reguły?", isPresented: $confirmSave,
                         message: "Obecna lista reguł zostanie nadpisana (można cofnąć tuż po zapisie).", actionTitle: "Zapisz") {
                    Task { if await vm.replaceAllRules(with: text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { dismiss() } }
                }
                .onAppear { text = vm.userRuleLines.joined(separator: "\n") }
        }
    }
}

struct RewriteEditorTarget: Identifiable {
    let id = UUID()
    let entry: RewriteEntry?
}

private struct RewriteEditor: View {
    let target: RewriteEditorTarget
    @ObservedObject var vm: FiltersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    @State private var answer = ""
    @State private var enabled = true
    @State private var confirmSave = false
    @FocusState private var focus: Field?

    private enum Field { case domain, answer }
    private var domainError: String? { Validators.rewriteDomainError(domain) }
    private var answerError: String? { Validators.rewriteAnswerError(answer) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Domena (np. nas.home lub *.example.org)", text: $domain)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .domain).submitLabel(.next).onSubmit { focus = .answer }
                    FieldError(message: domainError)
                    TextField("Odpowiedź (IP lub CNAME)", text: $answer)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .answer).submitLabel(.done)
                    FieldError(message: answerError)
                    Toggle("Włączone", isOn: $enabled)
                }
            }
            .navigationTitle(target.entry == nil ? "Nowe przepisanie" : "Edytuj przepisanie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { confirmSave = true }
                        .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || answer.trimmingCharacters(in: .whitespaces).isEmpty
                                  || domainError != nil || answerError != nil)
                }
            }
            .confirm("Zapisać przepisanie?", isPresented: $confirmSave, message: "\(domain) → \(answer)", actionTitle: "Zapisz") {
                Task {
                    let d = domain.trimmingCharacters(in: .whitespaces)
                    let a = answer.trimmingCharacters(in: .whitespaces)
                    let ok: Bool
                    if let entry = target.entry {
                        ok = await vm.updateRewrite(entry, domain: d, answer: a, enabled: enabled)
                    } else {
                        ok = await vm.addRewrite(domain: d, answer: a)
                    }
                    if ok { dismiss() }
                }
            }
            .onAppear {
                domain = target.entry?.domain ?? ""
                answer = target.entry?.answer ?? ""
                enabled = target.entry?.enabled ?? true
                if target.entry == nil { focus = .domain }
            }
        }
        .presentationDetents([.medium])
    }
}
