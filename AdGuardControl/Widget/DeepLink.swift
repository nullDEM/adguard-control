import Foundation

enum AppTab: String, CaseIterable {
    case dashboard, protection, querylog, filters, more
}

/// Adresy `adguardcontrol://open?tab=…&profile=…` używane przez widgety do otwierania właściwego ekranu.
struct DeepLink: Equatable {
    static let scheme = "adguardcontrol"

    var tab: AppTab
    var profileID: UUID?

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "tab", value: tab.rawValue)]
            + (profileID.map { [URLQueryItem(name: "profile", value: $0.uuidString)] } ?? [])
        return components.url!
    }

    /// Zwraca `nil` dla obcych schematów i nieznanych zakładek – aplikacja ignoruje takie adresy.
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let tabName = items.first(where: { $0.name == "tab" })?.value,
              let tab = AppTab(rawValue: tabName) else { return nil }
        self.tab = tab
        self.profileID = items.first(where: { $0.name == "profile" })?.value.flatMap(UUID.init(uuidString:))
    }

    init(tab: AppTab, profileID: UUID? = nil) {
        self.tab = tab
        self.profileID = profileID
    }
}
