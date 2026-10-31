import Foundation
import SwiftUI
import UIKit

struct Toast: Identifiable {
    enum Style { case success, error }
    let id = UUID()
    let text: String
    let style: Style
    var undo: (() async -> Void)?
}

/// Globalny stan aplikacji: profile, aktywny klient API, komunikaty.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var profiles: [ServerProfile]
    @Published private(set) var activeProfileID: UUID?
    @Published var toast: Toast?
    @Published var selectedTab: AppTab = .dashboard
    /// Zwiększany po powrocie aplikacji na pierwszy plan i po odzyskaniu sieci – ekrany odświeżają wtedy dane.
    @Published private(set) var refreshTrigger = 0

    private let profileStore: ProfileStore
    private let passwords: PasswordStoring
    private let sessionFactory: () -> URLSession
    private let tailscaleProbe: TailscaleProbing
    private var toastTask: Task<Void, Never>?
    private var cachedClient: (id: UUID, client: AdGuardAPIClient)?
    private let networkMonitor = NetworkMonitor()

    init(profileStore: ProfileStore = SharedStorage.makeProfileStore(),
         passwords: PasswordStoring = KeychainStore(),
         tailscaleProbe: TailscaleProbing = SystemTailscaleProbe(),
         monitorNetwork: Bool = false,
         sessionFactory: @escaping () -> URLSession = { AdGuardAPIClient.makeSession() }) {
        self.profileStore = profileStore
        self.passwords = passwords
        self.tailscaleProbe = tailscaleProbe
        self.sessionFactory = sessionFactory
        let loaded = profileStore.load()
        self.profiles = loaded
        let saved = profileStore.activeProfileID
        self.activeProfileID = loaded.contains { $0.id == saved } ? saved : loaded.first?.id
        passwords.migrateToSharedGroup(profileIDs: loaded.map(\.id))
        if monitorNetwork {
            networkMonitor.start { [weak self] in
                Task { @MainActor in self?.requestRefresh() }
            }
        }
    }

    /// Otwiera ekran wskazany w adresie z widgetu (i przełącza serwer, jeśli taki profil nadal istnieje).
    func open(_ link: DeepLink) {
        if let id = link.profileID, profiles.contains(where: { $0.id == id }), id != activeProfileID { select(id) }
        selectedTab = link.tab
    }

    /// Prosi aktywne ekrany o odświeżenie (po powrocie na pierwszy plan / odzyskaniu sieci).
    func requestRefresh() { refreshTrigger += 1 }

    var activeProfile: ServerProfile? { profiles.first { $0.id == activeProfileID } }

    /// Klient API dla aktywnego profilu (hasło pobierane z Keychain).
    var api: AdGuardAPIClient? {
        guard let profile = activeProfile else { return nil }
        if let cached = cachedClient, cached.id == profile.id { return cached.client }
        guard let client = makeClient(for: profile, password: passwords.password(for: profile.id) ?? "") else { return nil }
        cachedClient = (profile.id, client)
        return client
    }

    func makeClient(for profile: ServerProfile, password: String) -> AdGuardAPIClient? {
        // Profil zapisany wcześniej mógł mieć adres, który dziś jest niedozwolony – nie wysyłamy wtedy poświadczeń.
        guard let url = profile.url, (try? AddressPolicy.validate(url)) != nil else { return nil }
        return AdGuardAPIClient(baseURL: url, username: profile.username, password: password,
                                requireTailscale: profile.requireTailscale,
                                session: sessionFactory(), tailscaleProbe: tailscaleProbe)
    }

    // MARK: Profile

    /// Testuje połączenie danymi z formularza – bez zapisywania czegokolwiek.
    func testConnection(address: String, username: String, password: String, requireTailscale: Bool) async throws -> ServerStatus {
        if let message = ProfileValidator.usernameError(username) { throw APIError.unknown(message) }
        let url = try URLNormalizer.normalize(address)
        let client = AdGuardAPIClient(baseURL: url, username: username, password: password,
                                      requireTailscale: requireTailscale,
                                      session: sessionFactory(), tailscaleProbe: tailscaleProbe)
        return try await client.status()
    }

    func save(profile: ServerProfile, password: String?) throws {
        var profile = profile
        profile.address = try URLNormalizer.normalizedString(profile.address)
        if let message = ProfileValidator.nameError(profile.name) ?? ProfileValidator.usernameError(profile.username) {
            throw APIError.unknown(message)
        }
        if let password { try passwords.setPassword(password, for: profile.id) }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profileStore.save(profiles)
        cachedClient = nil
        WidgetRefresher.reload()
        if activeProfileID == nil { select(profile.id) }
    }

    func password(for profile: ServerProfile) -> String { passwords.password(for: profile.id) ?? "" }

    func select(_ id: UUID) {
        activeProfileID = id
        profileStore.activeProfileID = id
        cachedClient = nil
        WidgetRefresher.reload()
    }

    func delete(_ profile: ServerProfile) {
        passwords.deletePassword(for: profile.id)
        profiles.removeAll { $0.id == profile.id }
        profileStore.save(profiles)
        cachedClient = nil
        WidgetRefresher.reload()
        guard activeProfileID == profile.id else { return }
        if let first = profiles.first {
            select(first.id)
        } else {
            activeProfileID = nil
            profileStore.activeProfileID = nil
        }
    }

    // MARK: Komunikaty

    func notify(_ text: String, undo: (() async -> Void)? = nil) {
        show(Toast(text: text, style: .success, undo: undo))
    }

    func notifyError(_ error: Error) {
        let text = (error as? APIError)?.errorDescription ?? error.localizedDescription
        show(Toast(text: text, style: .error, undo: nil))
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func show(_ toast: Toast) {
        toastTask?.cancel()
        withAnimation { self.toast = toast }
        UIAccessibility.post(notification: .announcement, argument: toast.text)
        let seconds: UInt64 = toast.undo == nil ? 4 : 8
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { self?.toast = nil } }
        }
    }
}
