import SwiftUI

// MARK: - Motyw

enum Theme {
    static let protectionOn = Palette.green
    static let protectionOff = Palette.red
    static let accent = Palette.accent

    static func tint(for kind: QueryKind) -> Color {
        switch kind {
        case .blocked, .safeBrowsing, .parental, .blockedService: return Palette.red
        case .whitelisted: return Palette.green
        case .rewritten, .safeSearch: return Palette.blue
        case .error: return Palette.orange
        case .allowed: return .secondary
        }
    }
}

// MARK: - Stany

struct LoadStateView<Content: View>: View {
    let state: LoadState
    let retry: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Ładowanie…").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded:
            content()
        }
    }
}

struct ErrorStateView: View {
    let error: APIError
    let retry: () async -> Void
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: error.symbol)
                    .font(.system(size: iconSize))
                    .foregroundStyle(error.isAuthorizationProblem || error == .tailscaleRequired ? Palette.orange : Palette.red)
                    .accessibilityHidden(true)
                Text(error.title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(error.errorDescription ?? "Nieznany błąd")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if !error.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(error.diagnostics, id: \.self) { hint in
                            Label(hint, systemImage: "checkmark.circle")
                                .font(.footnote)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    Task { await retry() }
                } label: {
                    Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                        .foregroundStyle(Palette.onAccent)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 38

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: iconSize)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Informacja o funkcji niedostępnej przez API.
struct UnavailableNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Kafelki

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Potwierdzenia

/// Przełącznik, który przed zastosowaniem zmiany pyta o potwierdzenie.
/// Kiedy przełącznik pyta o potwierdzenie. Zgodnie z HIG alerty są zarezerwowane dla rzadkich lub ryzykownych działań;
/// zwykłe, odwracalne zmiany stosują się od razu (z komunikatem i przyciskiem „Cofnij”).
enum ToggleConfirmation {
    case none
    case whenTurningOff
    case whenTurningOn
}

struct ConfirmedToggle: View {
    let title: String
    let isOn: Bool
    var confirmation: ToggleConfirmation = .none
    var message: String = "Ta zmiana zostanie od razu zastosowana na serwerze."
    let action: (Bool) async -> Void

    @State private var pending = false
    @State private var showAlert = false

    private func needsConfirmation(_ newValue: Bool) -> Bool {
        switch confirmation {
        case .none: return false
        case .whenTurningOff: return !newValue
        case .whenTurningOn: return newValue
        }
    }

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { newValue in
            if needsConfirmation(newValue) {
                pending = newValue
                showAlert = true
            } else {
                Task { await action(newValue) }
            }
        }))
        .alert(pending ? "Włączyć: \(title)?" : "Wyłączyć: \(title)?", isPresented: $showAlert) {
            Button(pending ? "Włącz" : "Wyłącz", role: pending ? nil : .destructive) {
                let value = pending
                Task { await action(value) }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// Potwierdzenie operacji (np. zapis, usunięcie).
    func confirm(_ title: String, isPresented: Binding<Bool>, message: String? = nil,
                 actionTitle: String = "Potwierdź", destructive: Bool = false,
                 action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(actionTitle, role: destructive ? .destructive : nil, action: action)
            Button("Anuluj", role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
    }
}

// MARK: - Toast

struct ToastOverlay: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = app.toast {
                HStack(spacing: 12) {
                    Image(systemName: toast.style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(toast.style == .success ? Palette.green : Palette.orange)
                    Text(toast.text).font(.subheadline).lineLimit(3)
                    Spacer(minLength: 4)
                    if let undo = toast.undo {
                        Button("Cofnij") {
                            app.dismissToast()
                            Task { await undo() }
                        }
                        .font(.subheadline.bold())
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 8, y: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { app.dismissToast() }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: app.toast?.id)
        .allowsHitTesting(app.toast != nil)
    }
}

// MARK: - Wiersz zapytania

struct QueryRow: View {
    let item: QueryLogItem

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.tint(for: item.kind)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.domain).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text("\(item.clientDisplayName) · \(item.question?.type ?? "") · \(item.kind.title)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Formatting.time(item.time)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BarRow: View {
    let name: String
    let value: Double
    let maximum: Double
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Formatting.number(Int(value))).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule().fill(tint.opacity(0.7))
                    .frame(width: max(4, proxy.size.width * (maximum > 0 ? value / maximum : 0)))
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Edytor listy tekstowej (jedna pozycja na linię).
struct LinesEditor: View {
    let title: String
    @Binding var text: String
    var footer: String?

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 90)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

/// Edytor listy napisów (jedna pozycja na linię) z własnym stanem tekstu.
/// Dzięki temu Enter nie jest "zjadany" przez normalizację, a model dostaje oczyszczoną listę.
struct ListEditor: View {
    let title: String
    @Binding var items: [String]?
    var footer: String?

    @State private var text = ""

    var body: some View {
        LinesEditor(title: title, text: $text, footer: footer)
            .onAppear { text = (items ?? []).joined(separator: "\n") }
            .onChange(of: text) { _, new in
                let parsed = Formatting.lines(new)
                if parsed != (items ?? []) { items = parsed }
            }
            .onChange(of: items) { _, new in
                // Zmiana z zewnątrz (np. „Cofnij zmiany”, odświeżenie) – nadpisz tekst tylko gdy się różni.
                if Formatting.lines(text) != (new ?? []) { text = (new ?? []).joined(separator: "\n") }
            }
    }
}
