import Foundation

enum StatsRange: String, CaseIterable, Identifiable {
    case full, hour, day, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return "Cały okres"
        case .hour: return "1 godz."
        case .day: return "24 godz."
        case .week: return "7 dni"
        }
    }
    /// Parametr `recent` w milisekundach (wielokrotność godziny).
    var recentMs: Int? {
        switch self {
        case .full: return nil
        case .hour: return 3_600_000
        case .day: return 86_400_000
        case .week: return 604_800_000
        }
    }
}

@MainActor
final class DashboardViewModel: BaseViewModel {
    @Published var status: ServerStatus?
    @Published var stats: Stats?
    @Published var recent: [QueryLogItem] = []
    @Published var range: StatsRange = .full
    /// Czas przechowywania statystyk na serwerze (ms) – parametr `recent` nie może go przekraczać.
    @Published var retentionMs: Double?

    var availableRanges: [StatsRange] { Self.ranges(retentionMs: retentionMs) }

    static func ranges(retentionMs: Double?) -> [StatsRange] {
        StatsRange.allCases.filter { range in
            guard let recent = range.recentMs else { return true }
            guard let retentionMs else { return true }
            return Double(recent) <= retentionMs
        }
    }

    override func refresh() async {
        if retentionMs == nil, let config = try? await api?.statsConfig() {
            retentionMs = config.interval
            if !availableRanges.contains(range) { range = .full }
        }
        let range = self.range
        await load { api in
            async let status = api.status()
            async let stats = api.stats(recentMs: range.recentMs)
            async let log = api.queryLog(QueryLogParams(limit: 10))
            let (s, st, l) = try await (status, stats, log)
            self.status = s
            self.stats = st
            self.recent = l.data ?? []
        }
    }

    func setProtection(enabled: Bool, durationMs: UInt64? = nil) async {
        if await changeProtection(enabled: enabled, durationMs: durationMs) { await refresh() }
    }
}
