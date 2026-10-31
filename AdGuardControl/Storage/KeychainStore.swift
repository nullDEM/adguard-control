import Foundation
import Security

/// Abstrakcja przechowywania haseł (Keychain w aplikacji, pamięć w testach).
protocol PasswordStoring: AnyObject {
    func password(for profileID: UUID) -> String?
    func setPassword(_ password: String, for profileID: UUID) throws
    func deletePassword(for profileID: UUID)
    /// Przenosi hasła zapisane w starszych wersjach do wspólnej grupy Keychain (tylko prawdziwy Keychain).
    func migrateToSharedGroup(profileIDs: [UUID])
}

extension PasswordStoring {
    func migrateToSharedGroup(profileIDs: [UUID]) {}
}

enum KeychainError: Error, LocalizedError {
    case status(OSStatus)
    var errorDescription: String? {
        switch self {
        case .status(let code): return "Błąd Keychain (\(code))."
        }
    }
}

final class KeychainStore: PasswordStoring {
    private let service: String

    init(service: String = "pl.adguardcontrol.app.credentials") {
        self.service = service
    }

    private func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    func password(for profileID: UUID) -> String? {
        var query = query(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, for profileID: UUID) throws {
        let data = Data(password.utf8)
        let base = query(for: profileID)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            // Widgety odświeżają się w tle, także przy zablokowanym ekranie – po pierwszym odblokowaniu po restarcie.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    func deletePassword(for profileID: UUID) {
        SecItemDelete(query(for: profileID) as CFDictionary)
    }

    /// Przenosi hasła zapisane przed dodaniem widgetów do wspólnej grupy Keychain (pierwsza grupa z uprawnień)
    /// i ustawia dostępność wymaganą przez odświeżanie w tle.
    /// Najpierw dodaje kopię w nowej grupie i dopiero po sukcesie usuwa starą – hasło nie może zniknąć po drodze.
    /// Wykonuje się raz (flaga w `defaults`); po błędzie próbuje przy następnym uruchomieniu.
    func migrateToSharedGroup(profileIDs: [UUID]) {
        migrateToSharedGroup(profileIDs: profileIDs, defaults: SharedStorage.defaults)
    }

    func migrateToSharedGroup(profileIDs: [UUID], defaults: UserDefaults) {
        let flag = "keychain.sharedGroupMigrated.\(service)"
        guard !defaults.bool(forKey: flag) else { return }
        var allSucceeded = true
        for id in profileIDs {
            var lookup = query(for: id)
            lookup[kSecReturnAttributes as String] = true
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
                  let item = result as? [String: Any],
                  let data = item[kSecValueData as String] as? Data,
                  let oldGroup = item[kSecAttrAccessGroup as String] as? String else { continue }

            var add = query(for: id)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                var remove = query(for: id)
                remove[kSecAttrAccessGroup as String] = oldGroup
                SecItemDelete(remove as CFDictionary)
            case errSecDuplicateItem:
                break   // kopia w docelowej grupie już istnieje – stary wpis zostaje nietknięty
            default:
                allSucceeded = false
            }
        }
        if allSucceeded { defaults.set(true, forKey: flag) }
    }
}

final class InMemoryPasswordStore: PasswordStoring {
    private var storage: [UUID: String] = [:]
    func password(for profileID: UUID) -> String? { storage[profileID] }
    func setPassword(_ password: String, for profileID: UUID) throws { storage[profileID] = password }
    func deletePassword(for profileID: UUID) { storage[profileID] = nil }
}
