import Foundation
import Observation

import SwiftData

@MainActor
@Observable
final class RequestListViewModel {
    private(set) var requests: [SeerrMediaRequest] = []
    private var enrichments: [RequestEnrichmentResult] = []
    private(set) var requestCount: SeerrRequestCount?
    private(set) var totalCount: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var error: String?
    private(set) var actionSuccessMessage: String?

    var selectedFilter: RequestFilter = .all
    var selectedMediaType: RequestMediaType = .all
    var sortOrder: RequestSortOrder = .dateDesc

    private let apiClient: SeerrAPIClient
    private var modelContext: ModelContext?
    private var currentSkip: Int = 0
    private let pageSize: Int = 20
    private var hasLoadedRequests = false

    init(apiClient: SeerrAPIClient, modelContext: ModelContext? = nil) {
        self.apiClient = apiClient
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    var sortedRequests: [SeerrMediaRequest] {
        switch sortOrder {
        case .dateDesc: requests.sorted { $0.id > $1.id }
        case .dateAsc:  requests.sorted { $0.id < $1.id }
        case .title:
            requests.sorted {
                resolvedTitle(for: $0).localizedCaseInsensitiveCompare(resolvedTitle(for: $1)) == .orderedAscending
            }
        }
    }

    var hasMore: Bool {
        currentSkip + pageSize < totalCount
    }

    var pendingRequests: [SeerrMediaRequest] {
        sortedRequests.filter { $0.requestStatus == .pending }
    }

    func loadRequests() async {
        isLoading = true
        error = nil
        currentSkip = 0
        enrichments = []

        if !hasLoadedRequests, let context = modelContext, selectedFilter == .all, selectedMediaType == .all {
            let baseURL = apiClient.baseURL
            let descriptor = FetchDescriptor<CachedRequestItem>(
                predicate: #Predicate { $0.serverURL == baseURL }
            )
            if let cached = try? context.fetch(descriptor), !cached.isEmpty {
                requests = cached.compactMap { $0.toRequest }
                hasLoadedRequests = true
            }
        }

        do {
            async let requestsLoad = apiClient.getRequests(
                take: pageSize,
                skip: 0,
                filter: selectedFilter.apiValue,
                mediaType: selectedMediaType.apiValue
            )
            async let countLoad = apiClient.getRequestCount()

            let (response, count) = try await (requestsLoad, countLoad)
            
            // Diffing for subtle update
            let newRequests = response.results
            if requests.isEmpty {
                requests = newRequests
            } else {
                let existingIDs = Set(requests.map(\.id))
                let newIDs = Set(newRequests.map(\.id))
                
                // If it's a completely new list (e.g. filter changed), just replace
                if existingIDs.isDisjoint(with: newIDs) {
                    requests = newRequests
                } else {
                    var updated = requests.filter { newIDs.contains($0.id) }
                    for req in newRequests {
                        if let idx = updated.firstIndex(where: { $0.id == req.id }) {
                            updated[idx] = req
                        } else {
                            updated.append(req)
                        }
                    }
                    requests = updated.sorted { $0.id > $1.id } // Basic sort initially
                }
            }
            
            totalCount = response.pageInfo.results ?? 0
            requestCount = count
            await enrichMissingTitles(for: response.results)
            hasLoadedRequests = true
            
            if selectedFilter == .all, selectedMediaType == .all, let context = modelContext {
                let baseURL = apiClient.baseURL
                let descriptor = FetchDescriptor<CachedRequestItem>(
                    predicate: #Predicate { $0.serverURL == baseURL }
                )
                if let existing = try? context.fetch(descriptor) {
                    for item in existing {
                        context.delete(item)
                    }
                }
                for req in newRequests {
                    if let data = try? JSONEncoder().encode(req) {
                        let cached = CachedRequestItem(serverURL: baseURL, requestId: req.id, requestData: data)
                        context.insert(cached)
                    }
                }
                try? context.save()
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    func loadRequestsIfNeeded() async {
        guard !hasLoadedRequests else { return }
        await loadRequests()
    }

    func loadMore() async {
        let nextSkip = currentSkip + pageSize
        do {
            let response = try await apiClient.getRequests(
                take: pageSize,
                skip: nextSkip,
                filter: selectedFilter.apiValue,
                mediaType: selectedMediaType.apiValue
            )
            requests.append(contentsOf: response.results)
            currentSkip = nextSkip
            await enrichMissingTitles(for: response.results)
        } catch {
            handleError(error)
        }
    }

    func resolvedTitle(for request: SeerrMediaRequest) -> String {
        enrichment(for: request.id)?.title ?? request.displayTitle
    }

    func resolvedPosterURL(for request: SeerrMediaRequest) -> URL? {
        request.media?.posterURL ?? enrichment(for: request.id)?.posterURL
    }

    func approveRequest(_ request: SeerrMediaRequest) async -> SeerrMediaRequest? {
        let title = resolvedTitle(for: request)
        do {
            let updatedRequest = try await apiClient.approveRequest(id: request.id)
            actionSuccessMessage = "Approved \(title)"
            await loadRequests()
            return updatedRequest
        } catch {
            handleError(error)
            return nil
        }
    }

    func declineRequest(_ request: SeerrMediaRequest) async -> SeerrMediaRequest? {
        let title = resolvedTitle(for: request)
        do {
            let updatedRequest = try await apiClient.declineRequest(id: request.id)
            actionSuccessMessage = "Declined \(title)"
            await loadRequests()
            return updatedRequest
        } catch {
            handleError(error)
            return nil
        }
    }

    func deleteRequest(_ request: SeerrMediaRequest) async {
        let title = resolvedTitle(for: request)
        do {
            try await apiClient.deleteRequest(id: request.id)
            requests.removeAll { $0.id == request.id }
            if totalCount > 0 { totalCount -= 1 }
            actionSuccessMessage = "Deleted \(title)"
        } catch {
            handleError(error)
        }
    }

    func retryRequest(_ request: SeerrMediaRequest) async {
        let title = resolvedTitle(for: request)
        do {
            _ = try await apiClient.retryRequest(id: request.id)
            actionSuccessMessage = "Retrying \(title)"
            await loadRequests()
        } catch {
            handleError(error)
        }
    }

    func approveRequests(ids: Set<Int>) async {
        guard !ids.isEmpty else { return }

        var successfulIDs: [Int] = []
        var failedIDs: [Int] = []

        for requestID in ids {
            do {
                _ = try await apiClient.approveRequest(id: requestID)
                successfulIDs.append(requestID)
            } catch {
                failedIDs.append(requestID)
            }
        }

        if !successfulIDs.isEmpty {
            actionSuccessMessage = successfulIDs.count == 1 ? "Approved 1 request" : "Approved \(successfulIDs.count) requests"
            await loadRequests()
        }

        if !failedIDs.isEmpty {
            self.error = failedIDs.count == 1
                ? "Failed to approve 1 request"
                : "Failed to approve \(failedIDs.count) of \(ids.count) requests"
        }
    }

    func declineRequests(ids: Set<Int>) async {
        guard !ids.isEmpty else { return }

        var successfulIDs: [Int] = []
        var failedIDs: [Int] = []

        for requestID in ids {
            do {
                _ = try await apiClient.declineRequest(id: requestID)
                successfulIDs.append(requestID)
            } catch {
                failedIDs.append(requestID)
            }
        }

        if !successfulIDs.isEmpty {
            actionSuccessMessage = successfulIDs.count == 1 ? "Declined 1 request" : "Declined \(successfulIDs.count) requests"
            await loadRequests()
        }

        if !failedIDs.isEmpty {
            self.error = failedIDs.count == 1
                ? "Failed to decline 1 request"
                : "Failed to decline \(failedIDs.count) of \(ids.count) requests"
        }
    }

    func applyUpdatedRequest(_ request: SeerrMediaRequest) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        }
    }

    func removeRequest(id: Int) {
        requests.removeAll { $0.id == id }
        if totalCount > 0 {
            totalCount -= 1
        }
    }

    func clearActionMessage() { actionSuccessMessage = nil }
    func clearError() { error = nil }

    private func handleError(_ error: Error) {
        guard !error.isCancellation else { return }
        self.error = error.localizedDescription
    }

    private func enrichMissingTitles(for requests: [SeerrMediaRequest]) async {
        let missingRequests = requests.filter { request in
            let existing = enrichment(for: request.id)
            let needsTitle = request.displayTitle == "Unknown" && existing?.title == nil
            let needsPoster = request.media?.posterURL == nil && existing?.posterURL == nil
            return (needsTitle || needsPoster) &&
                request.media?.tmdbId != nil &&
                request.type != nil
        }

        guard !missingRequests.isEmpty else { return }

        let apiClient = self.apiClient

        await withTaskGroup(of: RequestEnrichmentResult?.self) { group in
            for request in missingRequests {
                guard let tmdbId = request.media?.tmdbId, let type = request.type else { continue }

                group.addTask {
                    do {
                        switch type {
                        case "movie":
                            let detail = try await apiClient.getMovieDetail(tmdbId: tmdbId)
                            return RequestEnrichmentResult(
                                requestID: request.id,
                                title: detail.displayTitle,
                                posterURL: detail.posterURL
                            )
                        case "tv":
                            let detail = try await apiClient.getTVDetail(tmdbId: tmdbId)
                            return RequestEnrichmentResult(
                                requestID: request.id,
                                title: detail.displayTitle,
                                posterURL: detail.posterURL
                            )
                        default:
                            return nil
                        }
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                guard let result else { continue }
                if let index = enrichments.firstIndex(where: { $0.requestID == result.requestID }) {
                    enrichments[index] = enrichments[index].merged(with: result)
                } else {
                    enrichments.append(result.normalized)
                }
            }
        }
    }

    private func enrichment(for requestID: Int) -> RequestEnrichmentResult? {
        enrichments.first(where: { $0.requestID == requestID })
    }
}

private struct RequestEnrichmentResult {
    let requestID: Int
    let title: String?
    let posterURL: URL?

    var normalized: RequestEnrichmentResult {
        RequestEnrichmentResult(
            requestID: requestID,
            title: title == "Unknown" ? nil : title,
            posterURL: posterURL
        )
    }

    func merged(with other: RequestEnrichmentResult) -> RequestEnrichmentResult {
        let normalizedOther = other.normalized
        return RequestEnrichmentResult(
            requestID: requestID,
            title: title ?? normalizedOther.title,
            posterURL: posterURL ?? normalizedOther.posterURL
        )
    }
}

enum RequestFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case approved = "Approved"
    case processing = "Processing"
    case available = "Available"
    case failed = "Failed"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .all:        "all"
        case .pending:    "pending"
        case .approved:   "approved"
        case .processing: "processing"
        case .available:  "available"
        case .failed:     "failed"
        }
    }
}

enum RequestMediaType: String, CaseIterable, Identifiable {
    case all = "All"
    case movie = "Movies"
    case tv = "TV"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .all:   "all"
        case .movie: "movie"
        case .tv:    "tv"
        }
    }
}

enum RequestSortOrder: String, CaseIterable, Identifiable {
    case dateDesc = "Newest First"
    case dateAsc  = "Oldest First"
    case title    = "Title"

    var id: String { rawValue }
}

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        if let lureError = self as? LureError,
           case .networkError(let wrappedError) = lureError {
            return wrappedError.isCancellation
        }

        return false
    }
}
