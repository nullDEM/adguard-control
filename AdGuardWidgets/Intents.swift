import AppIntents
import WidgetKit

/// Serwer wybierany w konfiguracji widgetu.
struct ServerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Serwer"
    static var defaultQuery = ServerQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ServerEntity] {
        let all = try await suggestedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        SharedStorage.makeProfileStore().load().map { ServerEntity(id: $0.id, name: $0.name) }
    }
}

/// Czas pauzy wybierany w konfiguracji widgetu.
enum PauseOption: Int, AppEnum {
    case five = 5, ten = 10, thirty = 30, hour = 60

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Czas pauzy"
    static var caseDisplayRepresentations: [PauseOption: DisplayRepresentation] = [
        .five: "5 minut", .ten: "10 minut", .thirty: "30 minut", .hour: "1 godzina",
    ]

    var milliseconds: UInt64 { UInt64(rawValue) * 60_000 }
    var label: String { self == .hour ? "1 godz." : "\(rawValue) min" }
}

struct SelectServerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Serwer"
    static var description = IntentDescription("Wybierz serwer AdGuard Home. Bez wyboru widget pokazuje serwer aktywny w aplikacji.")

    @Parameter(title: "Serwer")
    var server: ServerEntity?

    @Parameter(title: "Czas pauzy", default: .ten)
    var pause: PauseOption
}

/// Przycisk w widgecie: włącza ochronę albo wstrzymuje ją na 10 minut.
struct ToggleProtectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Przełącz ochronę DNS"
    static var isDiscoverable = false

    @Parameter(title: "Profil") var profileID: String
    @Parameter(title: "Włącz") var enable: Bool
    @Parameter(title: "Pauza (min)") var pauseMinutes: Int

    init() {}
    init(profileID: UUID?, enable: Bool, pause: PauseOption = .ten) {
        self.profileID = profileID?.uuidString ?? ""
        self.enable = enable
        self.pauseMinutes = pause.rawValue
    }

    func perform() async throws -> some IntentResult {
        let loader = WidgetDataLoader.live()
        try await loader.setProtection(profileID: UUID(uuidString: profileID), enabled: enable,
                                       pauseMs: enable ? nil : (PauseOption(rawValue: pauseMinutes) ?? .ten).milliseconds)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
