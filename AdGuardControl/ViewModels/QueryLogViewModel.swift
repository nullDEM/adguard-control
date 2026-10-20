import Foundation

@MainActor
final class QueryLogViewModel: BaseViewModel {
    static let pageSize = 50

    @Published var items: [QueryLogItem] = [] { didSet { recomputeVisible() } }
    @Published var search = ""
    @Published var clientFilter = "" { didSet { recomputeVisible() } }
    @Published var statusFilter: QueryStatusFilter = .all
    @Published var timeRange: QueryTimeRange = .all { didSet { recomputeVisible() } }
    @Published var canLoadMore = false
    @Published var isLoadingMore = false
    /// Elementy po filtrach lokalnych (klient, czas) – liczone raz po zmianie danych, nie przy każdym renderze.
    @Published private(set) var visibleItems: [QueryLogItem] = []

    /// Opóźnienie wyszukiwania po ostatnim naciśnięciu klawisza.
    static var searchDebounce: Duration = .milliseconds(350)

    private var oldest: String?
    /// Numer bieżącego zapytania listy – strony ze starszych zapytań są odrzucane.
    private var generation = 0
    /// Trwa przeładowanie listy – dociąganie kolejnych stron jest wtedy zablokowane (kursor jest nieaktualny).
    private var isReloading = false
    private var searchTask: Task<Void, Never>?

    /// Filtry klienta i czasu stosowane lokalnie (API ich nie udostępnia).
    private func recomputeVisible() {
        let client = clientFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let cutoff = timeRange.interval.map { Date().addingTimeInterval(-$0) }
        guard !client.isEmpty || cutoff != nil else { visibleItems = items; return }
        visibleItems = items.filter { item in
            if !client.isEmpty {
                let haystack = [item.client, item.clientId, item.clientInfo?.name].compactMap { $0?.lowercased() }
                if !haystack.contains(where: { $0.contains(client) }) { return false }
            }
            if let cutoff, let date = Formatting.parseDate(item.time), date < cutoff { return false }
            return true
        }
    }

    override func refresh() async { await reload() }

    /// Wyszukiwanie „na żywo”: każde naciśnięcie klawisza anuluje poprzednie oczekiwanie i wywołanie sieciowe.
    func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.reload()
        }
    }

    /// Natychmiastowe wyszukiwanie (Enter) – pomija oczekiwanie.
    func submitSearch() async {
        searchTask?.cancel()
        await reload()
    }

    var hasActiveFilters: Bool {
        statusFilter != .all || timeRange != .all || !clientFilter.isEmpty || !search.isEmpty
    }

    func resetFilters() {
        searchTask?.cancel()
        search = ""
        clientFilter = ""
        statusFilter = .all
        timeRange = .all
    }

    private func params(olderThan: String? = nil) -> QueryLogParams {
        QueryLogParams(olderThan: olderThan, limit: Self.pageSize,
                       search: search.trimmingCharacters(in: .whitespaces),
                       reasons: statusFilter.reasons)
    }

    func reload() async {
        generation += 1
        let current = generation
        let request = params()
        isReloading = true
        defer { if current == generation { isReloading = false } }
        await load { [weak self] api in
            let log = try await api.queryLog(request)
            guard let self, current == self.generation else { throw CancellationError() }
            self.items = log.data ?? []
            self.oldest = log.oldest
            self.canLoadMore = (log.data?.count ?? 0) >= Self.pageSize
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isReloading, let api, let last = items.last?.time else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let log = try await api.queryLog(params(olderThan: last))
            guard current == generation else { return }   // filtry zmieniły się w trakcie – strona jest nieaktualna
            let page = log.data ?? []
            items.append(contentsOf: page)
            oldest = log.oldest
            canLoadMore = page.count >= Self.pageSize
        } catch {
            let apiError = Self.apiError(from: error)
            if apiError != .cancelled { app?.notifyError(apiError) }
        }
    }

    // MARK: Szybkie akcje

    func blockDomain(_ domain: String) async {
        await addUserRule(UserRule.blockRule(domain: domain), message: "Zablokowano \(domain)")
    }

    func allowDomain(_ domain: String) async {
        await addUserRule(UserRule.allowRule(domain: domain), message: "Dodano \(domain) do białej listy")
    }

    func addUserRule(_ rule: String, message: String? = nil) async {
        var previous: [String] = []
        await mutate(message ?? "Dodano regułę \(rule)", undo: { try await $0.setUserRules(previous) }) { api in
            previous = try await api.modifyUserRules { $0.contains(rule) ? nil : $0 + [rule] }
        }
    }
}
