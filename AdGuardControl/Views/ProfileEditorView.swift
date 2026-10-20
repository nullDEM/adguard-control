import SwiftUI

/// Lista profili serwerów z przełączaniem, edycją i usuwaniem.
struct ProfilesView: View {
    @EnvironmentObject private var app: AppState
    @State private var editing: ProfileEditorTarget?
    @State private var deleting: ServerProfile?

    var body: some View {
        List {
            Section {
                ForEach(app.profiles) { profile in
                    Button {
                        app.select(profile.id)
                        app.notify("Aktywny serwer: \(profile.name)")
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline).foregroundStyle(.primary)
                                Text(profile.address).font(.caption).foregroundStyle(.secondary)
                                if profile.requireTailscale {
                                    Label("Wymaga Tailscale", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if profile.id == app.activeProfileID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.protectionOn) }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = profile } label: { Label("Usuń", systemImage: "trash") }
                        Button { editing = ProfileEditorTarget(profile: profile) } label: { Label("Edytuj", systemImage: "pencil") }.tint(.blue)
                    }
                }
                Button { editing = ProfileEditorTarget(profile: nil) } label: {
                    Label("Dodaj serwer", systemImage: "plus.circle.fill")
                }
            } footer: { Text("Dotknij profil, aby go aktywować. Przesuń w lewo, aby edytować lub usunąć. Każdy serwer ma własny adres, dane logowania i hasło w Keychain.") }
        }
        .navigationTitle("Serwery")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = ProfileEditorTarget(profile: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Dodaj serwer")
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack { ProfileEditorView(profile: target.profile, isOnboarding: false) }
        }
        .confirm("Usunąć profil „\(deleting?.name ?? "")”?",
                 isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                 message: "Profil i zapisane hasło zostaną usunięte z tego iPhone’a. Serwer pozostaje bez zmian.",
                 actionTitle: "Usuń", destructive: true) {
            if let profile = deleting { app.delete(profile) }
        }
    }
}

struct ProfileEditorTarget: Identifiable {
    let id = UUID()
    let profile: ServerProfile?
}

struct ProfileEditorView: View {
    let profile: ServerProfile?
    let isOnboarding: Bool

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var requireTailscale = false
    @State private var preset: Preset = .custom
    @State private var testing = false
    @State private var testOutcome: TestOutcome?
    @State private var confirmSaveAnyway = false
    @State private var showTailscaleHelp = false
    @State private var tailscaleActive = SystemTailscaleProbe().isTailscaleActive()
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, address, username, password }

    private var addressError: String? { ProfileValidator.addressError(address) }
    private var usernameError: String? { ProfileValidator.usernameError(username) }
    private var transportWarning: String? { ProfileValidator.transportWarning(address: address, requireTailscale: requireTailscale) }
    private var canSubmit: Bool {
        !testing && !name.trimmingCharacters(in: .whitespaces).isEmpty && !address.isEmpty && !username.isEmpty
            && addressError == nil && usernameError == nil
    }

    enum Preset: String, CaseIterable, Identifiable {
        case custom = "Własny", tailscaleIP = "Tailscale IP", magicDNS = "MagicDNS"
        var id: String { rawValue }
        var template: String? {
            switch self {
            case .custom: return nil
            case .tailscaleIP: return "http://100.x.y.z:3000"
            case .magicDNS: return "http://adguard-home.tailnet-name.ts.net:3000"
            }
        }
    }

    enum TestOutcome {
        case success(ServerStatus)
        case failure(APIError)
    }

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        LogoMark(size: 56)
                        Text("Witaj w AdGuard Control").font(.title2.bold())
                        Text("Dodaj swój serwer AdGuard Home. Najlepiej połączyć się przez Tailscale – nie musisz wystawiać żadnego portu do internetu.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Profil") {
                TextField("Nazwa profilu (np. Raspberry Pi)", text: $name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .address }
            }

            Section {
                Picker("Preset", selection: $preset) {
                    ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: preset) { _, new in
                    if let template = new.template, address.isEmpty || Preset.allCases.contains(where: { $0.template == address }) {
                        address = template
                    }
                    requireTailscale = new != .custom ? true : requireTailscale
                }
                TextField("http://adres[:port]", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($focus, equals: .address)
                    .submitLabel(.next)
                    .onSubmit { focus = .username }
                if let addressError {
                    Label(addressError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                } else if let transportWarning {
                    Label(transportWarning, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if preset != .custom {
                    Text("Zamień szablon na prawdziwy adres. Adres IP znajdziesz w panelu Tailscale lub poleceniem `tailscale ip -4` na Raspberry Pi.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button { showTailscaleHelp = true } label: { Label("Jak znaleźć adres w Tailscale?", systemImage: "questionmark.circle") }
            } header: { Text("Adres serwera") } footer: {
                Text("Pełny adres z portem, np. http://100.x.y.z:3000, http://adguard-home:3000, http://adguard-home.tailnet-name.ts.net:3000 lub http://192.168.1.10:3000. Port musi być taki, jak w Twoim AdGuard Home: często 80 (wtedy go pomiń), czasem 3000. Obsługiwane są HTTP i HTTPS.")
            }

            Section("Logowanie") {
                TextField("Login", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                if let usernameError {
                    Label(usernameError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                }
                SecureField("Hasło", text: $password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await saveTapped() } } }
            }

            Section {
                Toggle("Wymagaj Tailscale", isOn: $requireTailscale)
                HStack {
                    Image(systemName: tailscaleActive ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(tailscaleActive ? .green : .secondary)
                    Text(tailscaleActive ? "Tailscale na iPhonie jest aktywny" : "Nie wykryto aktywnego Tailscale na iPhonie")
                        .font(.footnote)
                }
            } header: { Text("Tailscale") } footer: {
                Text("Po włączeniu aplikacja nie wyśle żadnego zapytania, dopóki iPhone nie ma aktywnego połączenia z Tailscale. Połączenie w tailnecie jest szyfrowane (WireGuard), więc HTTP jest tu akceptowalne – login i hasło AdGuard Home są nadal wymagane.")
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        Label("Testuj połączenie", systemImage: "bolt.horizontal")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing || address.isEmpty || username.isEmpty || addressError != nil || usernameError != nil)
                testResult
            }
        }
        .navigationTitle(profile == nil ? "Nowy serwer" : "Edytuj serwer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Zapisz") { Task { await saveTapped() } }
                    .disabled(!canSubmit)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            load()
            // Nowy profil: od razu pole nazwy (na ekranie powitalnym i w arkuszu „Dodaj serwer”).
            if profile == nil { focus = .name }
        }
        .sheet(isPresented: $showTailscaleHelp) { TailscaleHelpView() }
        .alert("Zapisać mimo błędu?", isPresented: $confirmSaveAnyway) {
            Button("Zapisz mimo to") { persist() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            if case .failure(let error) = testOutcome { Text(error.errorDescription ?? "") }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testOutcome {
        case .success(let status):
            Label("Połączono · AdGuard Home \(status.version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let error):
            VStack(alignment: .leading, spacing: 6) {
                Label(error.errorDescription ?? "Błąd", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                ForEach(error.diagnostics, id: \.self) { Text("• \($0)").font(.footnote).foregroundStyle(.secondary) }
            }
        case nil:
            EmptyView()
        }
    }

    private func load() {
        guard let profile else { return }
        name = profile.name
        address = profile.address
        username = profile.username
        password = app.password(for: profile)
        requireTailscale = profile.requireTailscale
        preset = TailscaleHelper.looksLikeTailnetHost(profile.host) ? (profile.host.hasSuffix(".ts.net") ? .magicDNS : .tailscaleIP) : .custom
    }

    private func runTest() async {
        testing = true
        testOutcome = nil
        defer { testing = false }
        do {
            let normalized = try URLNormalizer.normalizedString(address)
            address = normalized
            testOutcome = .success(try await app.testConnection(address: normalized, username: username, password: password,
                                                                 requireTailscale: requireTailscale))
        } catch {
            testOutcome = .failure(BaseViewModel.apiError(from: error))
        }
        tailscaleActive = SystemTailscaleProbe().isTailscaleActive()
    }

    private func saveTapped() async {
        await runTest()
        switch testOutcome {
        case .success: persist()
        case .failure: confirmSaveAnyway = true
        case nil: break
        }
    }

    private func persist() {
        var saved = profile ?? ServerProfile(name: name, address: address, username: username)
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.address = address
        saved.username = username
        saved.requireTailscale = requireTailscale
        do {
            try app.save(profile: saved, password: password)
            app.select(saved.id)
            app.notify("Zapisano profil „\(saved.name)”")
            dismiss()
        } catch {
            app.notifyError(error)
        }
    }
}

struct TailscaleHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Gdzie zainstalować Tailscale") {
                    Label("iPhone: zawsze – to samo konto co reszta tailnetu.", systemImage: "iphone")
                    Label("Zalecane: na urządzeniu z AdGuard Home. Adres 100.x.y.z lub MagicDNS.", systemImage: "checkmark.circle")
                    Label("Alternatywa: na innym komputerze w sieci jako „subnet router” (tailscale up --advertise-routes=IP/32, trasę zatwierdź w panelu). Wtedy w aplikacji wpisz zwykły adres LAN serwera.", systemImage: "point.3.connected.trianglepath.dotted")
                    Label("Sam komputer z Tailscale w sieci nie wystarczy – bez subnet routera nie da dostępu do AdGuard Home. Pełna instrukcja jest w README.", systemImage: "exclamationmark.triangle")
                }
                Section("Gdzie znaleźć adres Raspberry Pi") {
                    Label("Panel Tailscale: login.tailscale.com/admin/machines – kolumna „Addresses”.", systemImage: "globe")
                    Label("Na Raspberry Pi: `tailscale ip -4` zwraca adres 100.x.y.z.", systemImage: "terminal")
                    Label("Na Raspberry Pi: `tailscale status` pokazuje wszystkie urządzenia tailnetu.", systemImage: "list.bullet")
                    Label("MagicDNS: nazwa-urządzenia.tailnet-name.ts.net (nazwa tailnetu jest w panelu → DNS).", systemImage: "network")
                }
                Section("Port panelu") {
                    Text("Wpisz port, na którym działa panel AdGuard Home. Po zakończonej konfiguracji zwykle jest to 80 – wtedy pomiń go: http://100.x.y.z. Port 3000 jest typowy dla kreatora pierwszej konfiguracji. „Connection refused” najczęściej oznacza zły port.")
                        .font(.footnote)
                }
                Section("Format adresu") {
                    Text("http://100.x.y.z:3000").font(.system(.body, design: .monospaced))
                    Text("http://adguard-home:3000").font(.system(.body, design: .monospaced))
                    Text("http://adguard-home.tailnet-name.ts.net:3000").font(.system(.footnote, design: .monospaced))
                }
                Section("Uwaga") {
                    Text("Aplikacja nie instaluje ani nie konfiguruje Tailscale. Zainstaluj aplikację Tailscale na iPhonie, zaloguj się na to samo konto co na Raspberry Pi i włącz VPN.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Tailscale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
        }
    }
}

/// Menu serwerów dostępne na każdej zakładce: przełączanie, dodawanie i zarządzanie profilami.
struct ProfileMenu: View {
    @EnvironmentObject private var app: AppState
    @State private var editing: ProfileEditorTarget?
    @State private var showManage = false

    var body: some View {
        Menu {
            ForEach(app.profiles) { profile in
                Button {
                    if profile.id != app.activeProfileID {
                        app.select(profile.id)
                        app.notify("Aktywny serwer: \(profile.name)")
                    }
                } label: {
                    if profile.id == app.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button { editing = ProfileEditorTarget(profile: nil) } label: { Label("Dodaj serwer…", systemImage: "plus") }
            Button { showManage = true } label: { Label("Zarządzaj serwerami…", systemImage: "list.bullet") }
        } label: {
            Label(app.activeProfile?.name ?? "Serwer", systemImage: "server.rack")
                .labelStyle(.titleAndIcon)
                .font(.footnote)
        }
        .accessibilityLabel("Serwery")
        .sheet(item: $editing) { target in
            NavigationStack { ProfileEditorView(profile: target.profile, isOnboarding: false) }
        }
        .sheet(isPresented: $showManage) {
            NavigationStack {
                ProfilesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { showManage = false } } }
            }
        }
    }
}
