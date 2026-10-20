import Foundation

/// Dane wyświetlane przez widgety – jedno zdjęcie stanu serwera.
struct WidgetSnapshot: Equatable {
    enum Failure: Equatable {
        case noProfile          // brak skonfigurowanego serwera
        case unreachable        // brak połączenia / timeout / Tailscale wyłączony
        case unauthorized       // błędne hasło
        case other

        var message: String {
            switch self {
            case .noProfile: return "Dodaj serwer w aplikacji"
            case .unreachable: return "Serwer niedostępny"
            case .unauthorized: return "Błędne hasło"
            case .other: return "Błąd odczytu"
            }
        }
    }

    var profileID: UUID?
    var profileName: String
    var protectionEnabled: Bool
    /// Pozostały czas pauzy w milisekundach (gdy ochrona jest wstrzymana na czas).
    var pausedForMs: Int64?
    var totalQueries: Int
    var blockedQueries: Int
    var blockedPercent: Double
    var topBlocked: String?
    var version: String?
    var failure: Failure?
    var date: Date

    static func placeholder() -> WidgetSnapshot {
        WidgetSnapshot(profileID: nil, profileName: "Raspberry Pi", protectionEnabled: true, pausedForMs: nil,
                       totalQueries: 12_480, blockedQueries: 3_120, blockedPercent: 25, topBlocked: "ads.tracker.net",
                       version: nil, failure: nil, date: Date())
    }

    static func failed(_ failure: Failure, profile: ServerProfile?, date: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(profileID: profile?.id, profileName: profile?.name ?? "AdGuard", protectionEnabled: false,
                       pausedForMs: nil, totalQueries: 0, blockedQueries: 0, blockedPercent: 0, topBlocked: nil,
                       version: nil, failure: failure, date: date)
    }

    static func make(profile: ServerProfile, status: ServerStatus, stats: Stats, date: Date = Date()) -> WidgetSnapshot {
        let paused = status.protectionEnabled ? nil : status.protectionDisabledDuration.flatMap { $0 > 0 ? $0 : nil }
        return WidgetSnapshot(profileID: profile.id, profileName: profile.name,
                              protectionEnabled: status.protectionEnabled, pausedForMs: paused,
                              totalQueries: stats.totalQueries, blockedQueries: stats.totalBlocked,
                              blockedPercent: stats.blockedPercent,
                              topBlocked: TopEntry.entries(stats.topBlockedDomains).max { $0.value < $1.value }?.name,
                              version: status.version, failure: nil, date: date)
    }

    static func failure(for error: Error) -> Failure {
        let apiError: APIError
        if let known = error as? APIError { apiError = known }
        else if let urlError = error as? URLError { apiError = APIError.from(urlError: urlError) }
        else { apiError = .unknown(error.localizedDescription) }
        switch apiError {
        case .unauthorized, .forbidden: return .unauthorized
        case .timeout, .noConnection, .hostUnreachable, .tailscaleRequired: return .unreachable
        default: return .other
        }
    }
}

/// Pobiera dane dla widgetów: wybiera profil, czyta hasło z Keychain i pyta serwer.
struct WidgetDataLoader {
    var profiles: () -> [ServerProfile]
    var activeProfileID: () -> UUID?
    var password: (UUID) -> String?
    var session: () -> URLSession = { AdGuardAPIClient.makeSession() }
    var tailscaleProbe: TailscaleProbing = SystemTailscaleProbe()

    static func live() -> WidgetDataLoader {
        let store = SharedStorage.makeProfileStore()
        let keychain = KeychainStore()
        return WidgetDataLoader(profiles: { store.load() }, activeProfileID: { store.activeProfileID },
                                password: { keychain.password(for: $0) })
    }

    /// Profil z konfiguracji widgetu albo aktywny w aplikacji.
    func resolveProfile(id: UUID?) -> ServerProfile? {
        let all = profiles()
        if let id, let match = all.first(where: { $0.id == id }) { return match }
        if let active = activeProfileID(), let match = all.first(where: { $0.id == active }) { return match }
        return all.first
    }

    func client(for profile: ServerProfile) -> AdGuardAPIClient? {
        guard let url = profile.url, (try? AddressPolicy.validate(url)) != nil,
              let password = password(profile.id) else { return nil }
        return AdGuardAPIClient(baseURL: url, username: profile.username, password: password,
                                requireTailscale: profile.requireTailscale,
                                session: session(), tailscaleProbe: tailscaleProbe)
    }

    func load(profileID: UUID?) async -> WidgetSnapshot {
        guard let profile = resolveProfile(id: profileID) else { return .failed(.noProfile, profile: nil) }
        guard let client = client(for: profile) else { return .failed(.other, profile: profile) }
        do {
            async let status = client.status()
            async let stats = client.stats()
            return try await .make(profile: profile, status: status, stats: stats)
        } catch {
            return .failed(Self.failure(for: error), profile: profile)
        }
    }

    private static func failure(for error: Error) -> WidgetSnapshot.Failure { WidgetSnapshot.failure(for: error) }

    /// Włącza lub wstrzymuje ochronę wskazanego profilu (przycisk w widgecie).
    func setProtection(profileID: UUID?, enabled: Bool, pauseMs: UInt64? = nil) async throws {
        guard let profile = resolveProfile(id: profileID), let client = client(for: profile) else { throw APIError.invalidURL }
        try await client.setProtection(enabled: enabled, durationMs: pauseMs)
    }
}
