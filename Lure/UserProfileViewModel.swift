import Foundation
import Observation

@Observable
final class UserProfileViewModel {
    private(set) var user: SeerrUser?
    private(set) var quota: SeerrUserQuota?
    private(set) var recentRequests: [SeerrMediaRequest] = []
    private(set) var requestCountSummary: SeerrRequestCount?
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    private let apiClient: SeerrAPIClient

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    func load(user: SeerrUser) async {
        self.user = user
        isLoading = true
        error = nil

        do {
            async let quotaLoad = apiClient.getUserQuota(userId: user.id)
            async let requestsLoad = apiClient.getUserRequests(userId: user.id, take: 10, skip: 0)

            let (q, r) = try await (quotaLoad, requestsLoad)
            quota = q
            recentRequests = r.results
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
