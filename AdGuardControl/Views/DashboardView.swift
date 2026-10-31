import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = DashboardViewModel()
    @State private var pauseOption: PauseOption?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var shieldSize: CGFloat = 36

    var body: some View {
        NavigationStack {
            LoadStateView(state: vm.state, retry: vm.refresh) {
                ScrollView {
                    VStack(spacing: 16) {
                        protectionCard
                        tiles
                        chartCard
                        topList("Najczęstsze domeny", entries: vm.stats?.topQueriedDomains, tint: Theme.accent)
                        topList("Najczęściej blokowane", entries: vm.stats?.topBlockedDomains, tint: Palette.red)
                        topList("Najaktywniejsi klienci", entries: vm.stats?.topClients, tint: Theme.accent)
                        recentCard
                    }
                    .padding()
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("Przegląd")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Odśwież")
                }
            }
            .task(id: app.refreshTrigger) { vm.bind(app); await vm.refreshIfNeeded() }
            .confirm("Wstrzymać ochronę?", isPresented: Binding(get: { pauseOption != nil }, set: { if !$0 { pauseOption = nil } }),
                     message: pauseOption.map { "Ochrona DNS zostanie wyłączona na: \($0.title)." },
                     actionTitle: "Wstrzymaj") {
                if let option = pauseOption { Task { await vm.setProtection(enabled: false, durationMs: option.milliseconds) } }
            }
        }
    }

    // MARK: Sekcje

    private var protectionEnabled: Bool { vm.status?.protectionEnabled ?? false }

    private var protectionCard: some View {
        let tint = protectionEnabled ? Theme.protectionOn : Theme.protectionOff
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: protectionEnabled ? "shield.checkered" : "shield.slash")
                    .font(.system(size: shieldSize)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(protectionEnabled ? "Ochrona włączona" : "Ochrona wyłączona")
                        .font(.title3.bold()).foregroundStyle(tint)
                    if let remaining = vm.status?.protectionDisabledDuration, remaining > 0, !protectionEnabled {
                        Text("Wznowienie za \(Formatting.duration(milliseconds: remaining))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let version = vm.status?.version {
                        Text("AdGuard Home \(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            ConfirmedToggle(title: "Ochrona DNS", isOn: protectionEnabled, confirmation: .whenTurningOff,
                            message: "Wyłączenie ochrony zatrzyma blokowanie zapytań DNS dla wszystkich klientów.") { value in
                await vm.setProtection(enabled: value)
            }
            if protectionEnabled {
                Menu {
                    ForEach(PauseOption.allCases) { option in
                        Button(option.title) { pauseOption = option }
                    }
                } label: {
                    Label("Wstrzymaj na czas…", systemImage: "pause.circle")
                }
            }
        }
        .padding()
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1))
    }

    /// Przy największych rozmiarach tekstu kontrolka segmentowa się nie skaluje – wtedy używamy menu.
    @ViewBuilder private var rangePicker: some View {
        let picker = Picker("Zakres", selection: $vm.range) {
            ForEach(vm.availableRanges) { Text($0.title).tag($0) }
        }
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var tiles: some View {
        let stats = vm.stats
        return VStack(spacing: 12) {
            rangePicker
                .onChange(of: vm.range) { _, _ in Task { await vm.refresh() } }

            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                StatTile(title: "Zapytania DNS", value: Formatting.number(stats?.totalQueries ?? 0),
                         icon: "arrow.left.arrow.right", tint: Theme.accent)
                StatTile(title: "Zablokowane", value: Formatting.number(stats?.totalBlocked ?? 0),
                         icon: "hand.raised.fill", tint: Palette.red)
                StatTile(title: "Odsetek zablokowanych", value: Formatting.percent(stats?.blockedPercent ?? 0),
                         icon: "percent", tint: Palette.red)
                StatTile(title: "Aktywni klienci", value: Formatting.number(stats?.activeClients ?? 0),
                         icon: "person.2.fill", tint: Theme.accent)
                StatTile(title: "Śr. czas odpowiedzi", value: Formatting.milliseconds(seconds: stats?.avgProcessingTime ?? 0),
                         icon: "speedometer", tint: Theme.accent)
                StatTile(title: "Bezpieczne przeglądanie i rodzicielska",
                         value: Formatting.number((stats?.numReplacedSafebrowsing ?? 0) + (stats?.numReplacedParental ?? 0)),
                         icon: "lock.shield", tint: Palette.red)
            }
        }
    }

    private struct ChartPoint: Identifiable {
        var id: String { "\(series)-\(index)" }
        let index: Int
        let series: String
        let value: Int
    }

    private var chartPoints: [ChartPoint] {
        guard let stats = vm.stats else { return [] }
        let queries = stats.dnsQueries ?? []
        let blocked = stats.blockedFiltering ?? []
        return queries.enumerated().map { ChartPoint(index: $0.offset, series: "Wszystkie", value: $0.element) }
            + blocked.enumerated().map { ChartPoint(index: $0.offset, series: "Zablokowane", value: $0.element) }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aktywność DNS").font(.headline)
            if chartPoints.isEmpty {
                EmptyStateView(icon: "chart.xyaxis.line", title: "Brak danych do wykresu",
                               message: "Statystyki mogą być wyłączone w ustawieniach serwera.")
            } else {
                Chart(chartPoints) { point in
                    LineMark(x: .value(vm.stats?.timeUnits == "days" ? "Dzień" : "Godzina", point.index),
                             y: .value("Zapytania", point.value))
                        .foregroundStyle(by: .value("Seria", point.series))
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Indeks", point.index), y: .value("Zapytania", point.value), stacking: .unstacked)
                        .foregroundStyle(by: .value("Seria", point.series))
                        .opacity(0.12)
                        .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale(["Wszystkie": Theme.accent, "Zablokowane": Palette.red])
                .frame(height: 180)
                .accessibilityLabel("Wykres aktywności DNS")
            }
        }
        .padding()
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func topList(_ title: String, entries raw: [[String: Double]]?, tint: Color) -> some View {
        let entries = Array(TopEntry.entries(raw).prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if entries.isEmpty {
                Text("Brak danych").font(.footnote).foregroundStyle(.secondary)
            } else {
                let maximum = entries.map(\.value).max() ?? 1
                ForEach(entries) { BarRow(name: $0.name, value: $0.value, maximum: maximum, tint: tint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ostatnie zapytania").font(.headline)
            if vm.recent.isEmpty {
                Text("Brak zapytań").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(vm.recent) { item in
                    QueryRow(item: item)
                    if item.id != vm.recent.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum PauseOption: String, CaseIterable, Identifiable {
    case minute, tenMinutes, hour, day
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minute: return "1 minutę"
        case .tenMinutes: return "10 minut"
        case .hour: return "1 godzinę"
        case .day: return "24 godziny"
        }
    }
    var milliseconds: UInt64 {
        switch self {
        case .minute: return 60_000
        case .tenMinutes: return 600_000
        case .hour: return 3_600_000
        case .day: return 86_400_000
        }
    }
}
