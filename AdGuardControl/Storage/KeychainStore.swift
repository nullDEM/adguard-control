import Foundation
import Security

/// Abstrakcja przechowywania haseł (Keychain w aplikacji, pamięć w testach).
protocol PasswordStoring: AnyObject {
    func password(for profileID: UUID) -> String?
    func setPassword(_ password: String, for profileID: UUID) throws
    func deletePassword(for profileID: UUID)
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
    /// i ustawia dostępność wymaganą przez odświeżanie w tle. Bezpieczne do wielokrotnego wywołania.
    func migrateToSharedGroup(profileIDs: [UUID]) {
        for id in profileIDs {
            guard let password = password(for: id) else { continue }
            deletePassword(for: id)
            try? setPassword(password, for: id)
        }
    }
}

final class InMemoryPasswordStore: PasswordStoring {
    private var storage: [UUID: String] = [:]
    func password(for profileID: UUID) -> String? { storage[profileID] }
    func setPassword(_ password: String, for profileID: UUID) throws { storage[profileID] = password }
    func deletePassword(for profileID: UUID) { storage[profileID] = nil }
}
