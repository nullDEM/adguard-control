import AppIntents
import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var pause: PauseOption = .ten
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .placeholder())
    }

    func snapshot(for configuration: SelectServerIntent, in context: Context) async -> StatusEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectServerIntent, in context: Context) async -> Timeline<StatusEntry> {
        let entry = await entry(for: configuration)
        // Wstrzymana ochrona: odśwież po jej wygaśnięciu; w innych przypadkach co 15 minut (błąd – częściej).
        var next = Date().addingTimeInterval(entry.snapshot.failure == nil ? 15 * 60 : 5 * 60)
        if let paused = entry.snapshot.pausedForMs, paused > 0 {
            next = min(next, Date().addingTimeInterval(Double(paused) / 1000 + 2))
        }
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SelectServerIntent) async -> StatusEntry {
        let snapshot = await WidgetDataLoader.live().load(profileID: configuration.server?.id)
        return StatusEntry(date: Date(), snapshot: snapshot, pause: configuration.pause)
    }
}

struct AdGuardStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AdGuardStatus", intent: SelectServerIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(snapshot: entry.snapshot, pause: entry.pause, updated: entry.date)
        }
        .configurationDisplayName("AdGuard Home")
        .description("Stan ochrony DNS i statystyki. Przycisk włącza lub wstrzymuje ochronę.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Widoki

private enum WidgetTheme {
    static let accent = Palette.accent
    static let blocked = Palette.red
    /// Tekst na przycisku z wypełnieniem: biały w jasnym, czarny w ciemnym motywie (kontrast ≥ 4,5:1).
    static let onTint = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
}

extension WidgetSnapshot {
    var stateTitle: String {
        if let failure { return failure.message }
        if protectionEnabled { return "Ochrona włączona" }
        return pausedForMs != nil ? "Ochrona wstrzymana" : "Ochrona wyłączona"
    }
    var stateSymbol: String {
        if failure != nil { return "exclamationmark.triangle.fill" }
        return protectionEnabled ? "checkmark.shield.fill" : "shield.slash.fill"
    }
    var stateColor: Color {
        if failure != nil { return Palette.orange }
        return protectionEnabled ? Palette.green : Palette.red
    }
    var percentText: String { String(format: "%.0f%%", blockedPercent) }
    var queriesText: String { WidgetSnapshot.compact(totalQueries) }
    var blockedText: String { WidgetSnapshot.compact(blockedQueries) }

    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    var pause: PauseOption = .ten
    var updated: Date = .now

    private func link(_ tab: AppTab) -> URL { DeepLink(tab: tab, profileID: snapshot.profileID).url }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium.widgetBackground().widgetURL(link(.dashboard))
        default: small.widgetBackground().widgetURL(link(.dashboard))
        }
    }

    private var toggle: some View {
        let enable = !snapshot.protectionEnabled
        return Button(intent: ToggleProtectionIntent(profileID: snapshot.profileID, enable: enable, pause: pause)) {
            Label(enable ? "Włącz" : "Pauza \(pause.label)", systemImage: enable ? "play.fill" : "pause.fill")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(WidgetTheme.onTint)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(enable ? Palette.green : WidgetTheme.accent)
        .disabled(snapshot.failure != nil)
        .accessibilityLabel(enable ? "Włącz ochronę DNS" : "Wstrzymaj ochronę DNS na \(pause.label)")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.stateSymbol).foregroundStyle(snapshot.stateColor)
                Text(snapshot.profileName).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Text(snapshot.stateTitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if snapshot.failure == nil {
                Text(snapshot.percentText).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.blocked)
                Text("zablokowanych").font(.caption2).foregroundStyle(.secondary)
            }
            if snapshot.failure != .noProfile { toggle }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.stateSymbol).foregroundStyle(snapshot.stateColor)
                    Text(snapshot.profileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(snapshot.stateTitle).font(.footnote).foregroundStyle(.secondary)
                Text("Stan z \(updated.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if snapshot.failure != .noProfile { toggle }
            }
            if snapshot.failure == nil {
                VStack(alignment: .leading, spacing: 8) {
                    stat("Zapytania (24 h)", snapshot.queriesText, .primary)
                    stat("Zablokowane", "\(snapshot.blockedText) · \(snapshot.percentText)", WidgetTheme.blocked)
                    if let top = snapshot.topBlocked {
                        Link(destination: link(.querylog)) { stat("Najczęściej blokowana", top, .secondary) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: some ShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // Ekran blokady

    private var circular: some View {
        Group {
            if snapshot.failure != nil {
                ZStack { AccessoryWidgetBackground(); Image(systemName: snapshot.stateSymbol) }
            } else {
                Gauge(value: min(snapshot.blockedPercent, 100), in: 0...100) {
                    Image(systemName: snapshot.protectionEnabled ? "shield.fill" : "shield.slash")
                } currentValueLabel: {
                    Text(snapshot.percentText).font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityLabel("\(snapshot.stateTitle). Zablokowane \(snapshot.percentText)")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(snapshot.stateTitle, systemImage: snapshot.stateSymbol).font(.headline).lineLimit(1)
            if snapshot.failure == nil {
                Text("Zapytań: \(snapshot.queriesText)").font(.caption)
                Text("Zablokowane: \(snapshot.blockedText) (\(snapshot.percentText))").font(.caption)
            } else {
                Text(snapshot.profileName).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var inline: some View {
        Group {
            if snapshot.failure == nil {
                Label("\(snapshot.percentText) zablokowane", systemImage: snapshot.stateSymbol)
            } else {
                Label(snapshot.stateTitle, systemImage: snapshot.stateSymbol)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private extension View {
    func widgetBackground() -> some View {
        containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview(as: .systemSmall) {
    AdGuardStatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder())
}
