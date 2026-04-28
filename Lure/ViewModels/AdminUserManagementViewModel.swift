import Foundation
import Observation

@Observable
final class AdminUserManagementViewModel {
    private(set) var users: [SeerrUser] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var errorMessage: String?

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

    var totalUserCount: Int {
        max(totalResults, users.count)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await loadUsers()
    }

    func loadUsers() async {
        isLoading = true
        errorMessage = nil
        currentSkip = 0

        do {
            let response = try await apiClient.getUsers(take: pageSize, skip: 0)
            users = response.results
            totalResults = response.pageInfo.results ?? response.results.count
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard hasMore else { return }
        let nextSkip = currentSkip + pageSize

        do {
            let response = try await apiClient.getUsers(take: pageSize, skip: nextSkip)
            users.append(contentsOf: response.results)
            currentSkip = nextSkip
            totalResults = response.pageInfo.results ?? totalResults
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFromJellyfin() async {
        isImporting = true
        errorMessage = nil

        do {
            _ = try await apiClient.importUsersFromJellyfin()
            await loadUsers()
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    func deleteUser(_ user: SeerrUser) async {
        do {
            _ = try await apiClient.deleteUser(id: user.id)
            users.removeAll { $0.id == user.id }
            totalResults = max(0, totalResults - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyUpdatedUser(_ user: SeerrUser) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
