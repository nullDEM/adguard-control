import Foundation

/// Profile serwerów (bez haseł) w UserDefaults.
final class ProfileStore {
    private let defaults: UserDefaults
    private let profilesKey = "profiles.v1"
    private let activeKey = "profiles.active"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ServerProfile] {
        guard let data = defaults.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return [] }
        return profiles
    }

    func save(_ profiles: [ServerProfile]) {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: profilesKey) }
    }

    var activeProfileID: UUID? {
        get { defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: activeKey) }
    }
}
