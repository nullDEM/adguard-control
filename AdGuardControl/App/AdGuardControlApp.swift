import SwiftUI

@main
struct AdGuardControlApp: App {
    @StateObject private var app: AppState

    init() {
        #if DEBUG
        if UITestSupport.isActive {
            _app = StateObject(wrappedValue: UITestSupport.makeAppState())
            return
        }
        #endif
        _app = StateObject(wrappedValue: AppState(monitorNetwork: true))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if app.profiles.isEmpty {
                NavigationStack { ProfileEditorView(profile: nil, isOnboarding: true) }
            } else {
                MainTabView()
                    .id(app.activeProfileID)
            }
            ToastOverlay()
            // Podgląd w przełączniku aplikacji nie może pokazywać zapytań DNS ani danych serwera.
            if scenePhase != .active { PrivacyShield() }
        }
        .tint(Theme.accent)
        .onOpenURL { url in
            if let link = DeepLink(url: url) { app.open(link) }
        }
        .onChange(of: scenePhase) { old, new in
            if new == .active, old != .active { app.requestRefresh() }
        }
    }
}

/// Nakładka zasłaniająca zawartość, gdy aplikacja nie jest aktywna.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            LogoMark(size: 96)
        }
        .ignoresSafeArea()
        .transition(.identity)
        .accessibilityHidden(true)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            DashboardView().tabItem { Label("Przegląd", systemImage: "gauge.with.dots.needle.67percent") }.tag(AppTab.dashboard)
            ProtectionView().tabItem { Label("Ochrona", systemImage: "shield.lefthalf.filled") }.tag(AppTab.protection)
            QueryLogView().tabItem { Label("Dziennik", systemImage: "list.bullet.rectangle") }.tag(AppTab.querylog)
            FiltersView().tabItem { Label("Filtry", systemImage: "line.3.horizontal.decrease.circle") }.tag(AppTab.filters)
            MoreView().tabItem { Label("Więcej", systemImage: "ellipsis.circle") }.tag(AppTab.more)
        }
    }
}

/// Zakładka „Więcej” z jednym wspólnym stosem nawigacji (bez zagnieżdżonych pasków).
struct MoreView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Serwery") {
                    NavigationLink { ProfilesView() } label: {
                        LabeledContent {
                            Text(app.activeProfile?.name ?? "—").foregroundStyle(.secondary)
                        } label: {
                            Label("\(app.profiles.count == 1 ? "Serwer" : "Serwery") (\(app.profiles.count))", systemImage: "server.rack")
                        }
                    }
                }
                Section("Narzędzia") {
                    NavigationLink { ClientsView() } label: { Label("Klienci", systemImage: "person.2") }
                    NavigationLink { DNSView() } label: { Label("DNS", systemImage: "network") }
                    NavigationLink { DHCPView() } label: { Label("DHCP", systemImage: "externaldrive.connected.to.line.below") }
                    NavigationLink { SettingsView() } label: { Label("Ustawienia", systemImage: "gearshape") }
                }
            }
            .navigationTitle("Więcej")
        }
    }
}
