import Foundation
import Observation

enum AdminIssueFilter: String, CaseIterable, Identifiable {
    case open = "Open"
    case resolved = "Resolved"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .open: "open"
        case .resolved: "resolved"
        }
    }
}

@Observable
final class AdminIssueListViewModel {
    private(set) var issues: [SeerrIssue] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    var selectedFilter: AdminIssueFilter = .open

    private let apiClient: SeerrAPIClient
    private let pageSize = 20
    private var currentSkip = 0
    private var totalResults = 0
    private var hasLoaded = false

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    var hasMore: Bool {
        currentSkip + pageSize < totalResults
    }

    var totalIssueCount: Int {
        max(totalResults, issues.count)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await loadIssues()
    }

    func loadIssues() async {
        isLoading = true
        errorMessage = nil
        currentSkip = 0

        do {
            let response = try await apiClient.getIssues(
                take: pageSize,
                skip: 0,
                sort: "createdAt",
                filter: selectedFilter.apiValue
            )
            issues = response.results
            totalResults = response.pageInfo.results ?? response.results.count
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextSkip = currentSkip + pageSize

        do {
            let response = try await apiClient.getIssues(
                take: pageSize,
                skip: nextSkip,
                sort: "createdAt",
                filter: selectedFilter.apiValue
            )
            let existingIds = Set(issues.map(\.id))
            let newIssues = response.results.filter { !existingIds.contains($0.id) }
            issues.append(contentsOf: newIssues)
            currentSkip = nextSkip
            totalResults = response.pageInfo.results ?? totalResults
            isLoadingMore = false
        } catch {
            errorMessage = error.localizedDescription
            isLoadingMore = false
        }
    }

    func refreshIssue(_ issue: SeerrIssue) {
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            issues[index] = issue
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
