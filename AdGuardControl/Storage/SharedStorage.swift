import Foundation
import WidgetKit

/// Współdzielenie profili (bez haseł) między aplikacją a widgetami przez App Group.
/// Hasła nadal są wyłącznie w Keychain – widgety czytają je ze wspólnej grupy dostępu Keychain
/// (patrz `AdGuardControl.entitlements`).
enum SharedStorage {
    static let appGroup = "group.pl.adguardcontrol.shared"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Magazyn profili w App Group; przy pierwszym uruchomieniu po aktualizacji przenosi profile z `UserDefaults.standard`.
    static func makeProfileStore() -> ProfileStore {
        migrate(from: .standard, to: defaults)
        return ProfileStore(defaults: defaults)
    }

    /// Kopiuje profile ze starego miejsca, o ile w nowym nic jeszcze nie ma.
    static func migrate(from legacyDefaults: UserDefaults, to targetDefaults: UserDefaults) {
        let target = ProfileStore(defaults: targetDefaults)
        guard target.load().isEmpty else { return }
        let legacy = ProfileStore(defaults: legacyDefaults)
        let profiles = legacy.load()
        guard !profiles.isEmpty else { return }
        target.save(profiles)
        target.activeProfileID = legacy.activeProfileID
    }
}

enum WidgetRefresher {
    /// Prosi system o odświeżenie widgetów (po zmianie profilu, hasła lub stanu ochrony).
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
