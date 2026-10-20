import Foundation
import Network

/// Obserwuje dostępność sieci. Wywołuje `onRestore` przy przejściu z braku sieci do połączenia
/// (np. po włączeniu Tailscale lub Wi-Fi), żeby ekrany mogły się automatycznie odświeżyć.
final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "pl.adguardcontrol.network-monitor")
    private var wasSatisfied: Bool?

    func start(onRestore: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let previous = self.wasSatisfied
            self.wasSatisfied = satisfied
            // Pierwszy odczyt (previous == nil) nie jest „odzyskaniem” połączenia.
            if satisfied, previous == false { onRestore() }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }

    deinit { monitor.cancel() }
}
