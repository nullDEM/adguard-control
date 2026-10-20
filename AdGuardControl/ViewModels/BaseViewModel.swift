import Foundation

enum LoadState: Equatable {
    case idle, loading, loaded
    case failed(APIError)
}

/// Wspólna logika ładowania i zmian z obsługą błędów, komunikatów i undo.
@MainActor
class BaseViewModel: ObservableObject {
    @Published var state: LoadState = .idle
    @Published var isBusy = false

    private(set) weak var app: AppState?

    /// Kiedy dane zostały ostatnio wczytane z powodzeniem.
    private(set) var lastLoaded: Date?
    /// Numer ostatniego wywołania `load` – pozwala ignorować wyniki i anulowania przestarzałych wywołań.
    private var loadCounter = 0
    private var loadTask: Task<Void, Error>?
    /// Odświeżanie wywołane automatycznie (wejście na ekran) może korzystać z cache; ręczne zawsze pobiera świeże dane.
    private var isAutomaticRefresh = false

    func bind(_ app: AppState) { self.app = app }

    var api: AdGuardAPIClient? { app?.api }

    static func apiError(from error: Error) -> APIError {
        if let apiError = error as? APIError { return apiError }
        if let urlError = error as? URLError { return APIError.from(urlError: urlError) }
        if error is CancellationError { return .cancelled }
        return .unknown(error.localizedDescription)
    }

    // MARK: Odświeżanie

    /// Nadpisywane przez podklasy – pobiera wszystkie dane ekranu.
    func refresh() async {}

    /// Czy dane są puste, błędne lub starsze niż `maxAge` sekund.
    func needsRefresh(maxAge: TimeInterval = 20, now: Date = Date()) -> Bool {
        if case .failed = state { return true }
        guard let lastLoaded else { return true }
        return now.timeIntervalSince(lastLoaded) > maxAge
    }

    /// Odświeżenie przy wejściu na ekran / powrocie do aplikacji: pomija pobieranie, gdy dane są świeże.
    func refreshIfNeeded(maxAge: TimeInterval = 20) async {
        guard needsRefresh(maxAge: maxAge) else { return }
        isAutomaticRefresh = true
        defer { isAutomaticRefresh = false }
        await refresh()
    }

    // MARK: Ładowanie i zmiany

    /// Ładowanie danych: przy pierwszym wczytaniu pełny stan, przy odświeżeniu – zachowuje zawartość.
    /// Nowe wywołanie anuluje poprzednie (także zapytania sieciowe), a anulowanie ekranu anuluje zapytania.
    func load(_ work: @escaping (AdGuardAPIClient) async throws -> Void) async {
        guard let api else { state = .failed(.invalidURL); return }
        loadCounter += 1
        let ticket = loadCounter
        if !isAutomaticRefresh { api.invalidateCache() }
        loadTask?.cancel()
        let hadContent = state == .loaded
        if !hadContent { state = .loading }

        let task = Task { try await work(api) }
        loadTask = task
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard ticket == loadCounter else { return }
            state = .loaded
            lastLoaded = Date()
        } catch {
            // Wynik przestarzałego wywołania (zastąpionego nowszym) nie może zmienić stanu.
            guard ticket == loadCounter else { return }
            let apiError = Self.apiError(from: error)
            if apiError == .cancelled { if !hadContent { state = .idle }; return }
            if hadContent {
                app?.notifyError(apiError)
            } else {
                state = .failed(apiError)
            }
        }
    }

    /// Operacja zmieniająca konfigurację. Zwraca `true` po sukcesie.
    @discardableResult
    func mutate(_ success: String?, undo: ((AdGuardAPIClient) async throws -> Void)? = nil,
                work: (AdGuardAPIClient) async throws -> Void) async -> Bool {
        guard let api else { app?.notifyError(APIError.invalidURL); return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await work(api)
            if let success {
                if let undo {
                    app?.notify(success) { [weak self] in
                        guard let self else { return }
                        _ = await self.mutate("Cofnięto zmianę", work: { try await undo($0) })
                    }
                } else {
                    app?.notify(success)
                }
            }
            return true
        } catch {
            let apiError = Self.apiError(from: error)
            if apiError != .cancelled { app?.notifyError(apiError) }
            return false
        }
    }
}

// MARK: - Wspólne operacje (jedna implementacja dla Dashboardu, Ochrony i Filtrów)

extension BaseViewModel {
    /// Włącza lub wstrzymuje ochronę DNS (pauza = `durationMs`). Zwraca `true` po sukcesie.
    func changeProtection(enabled: Bool, durationMs: UInt64? = nil) async -> Bool {
        let message = enabled ? "Ochrona DNS włączona" : (durationMs == nil ? "Ochrona DNS wyłączona" : "Ochrona wstrzymana")
        let done = await mutate(message, undo: { try await $0.setProtection(enabled: !enabled) }) {
            try await $0.setProtection(enabled: enabled, durationMs: durationMs)
        }
        if done { WidgetRefresher.reload() }
        return done
    }

    /// Zmienia tylko podane pola konfiguracji filtrowania, scalając je z aktualnym stanem serwera.
    func changeFiltering(enabled: Bool? = nil, interval: Int? = nil, message: String) async -> Bool {
        var previous: FilterConfig?
        return await mutate(message, undo: { api in
            if let previous { try await api.setFilteringConfig(previous) }
        }) { api in
            previous = try await api.updateFilteringConfig(enabled: enabled, interval: interval)
        }
    }
}
