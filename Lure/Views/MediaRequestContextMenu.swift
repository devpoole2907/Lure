import SwiftUI

// MARK: - Context menu for Seerr request actions on any SeerrMediaItem poster/cell

struct MediaRequestContextMenu: View {
    let mediaType: String
    let tmdbId: Int
    let title: String
    let mediaInfo: SeerrMediaInfo?
    let isKnownAvailable: Bool
    let apiClient: SeerrAPIClient
    let notificationCenter: InAppNotificationCenter
    let requestsCoordinator: RequestsCoordinator

    private var canRequestHD: Bool {
        mediaType != "person" &&
        !isKnownAvailable &&
        mediaInfo?.hasHDRequest != true
    }

    private var canRequest4K: Bool {
        mediaType != "person" &&
        mediaInfo?.has4KRequest != true
    }

    var body: some View {
        if canRequestHD {
            Button {
                submitRequest(is4k: false)
            } label: {
                Label("Request HD", systemImage: "arrow.down.circle")
            }
        }

        if canRequest4K {
            Button {
                submitRequest(is4k: true)
            } label: {
                Label("Request 4K", systemImage: "sparkles.tv")
            }
        }
    }

    private func submitRequest(is4k: Bool) {
        Task {
            do {
                try await request(is4k: is4k)
                await MainActor.run {
                    requestsCoordinator.markStale()
                    notificationCenter.show(LureBannerItem(
                        title: "Request Submitted",
                        message: "\(title) \(is4k ? "4K" : "HD") was requested.",
                        style: .success
                    ))
                }
            } catch {
                await MainActor.run {
                    notificationCenter.show(LureBannerItem(
                        title: "Request Failed",
                        message: error.localizedDescription,
                        style: .error
                    ))
                }
            }
        }
    }

    private func request(is4k: Bool) async throws {
        let seasons: [Int]?
        if mediaType == "tv" {
            let show = try await apiClient.getTVDetail(tmdbId: tmdbId)
            let requestableSeasons = show.requestableSeasonNumbers(is4k: is4k)
            guard !requestableSeasons.isEmpty else {
                throw MediaRequestError.noRequestableSeasons
            }
            seasons = requestableSeasons
        } else {
            seasons = nil
        }

        let body = SeerrCreateRequestBody(
            mediaType: mediaType,
            mediaId: tmdbId,
            is4k: is4k,
            serverId: nil,
            profileId: nil,
            rootFolder: nil,
            seasons: seasons,
            tags: nil,
            userId: nil
        )
        _ = try await apiClient.createRequest(body)
    }
}

// MARK: - Context menu wrapper for LibraryItem rows

struct LibraryItemRequestContextMenu: View {
    let item: LibraryItem
    let apiClient: SeerrAPIClient
    let notificationCenter: InAppNotificationCenter
    let requestsCoordinator: RequestsCoordinator

    var body: some View {
        MediaRequestContextMenu(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            mediaInfo: nil,
            isKnownAvailable: item.isAvailable,
            apiClient: apiClient,
            notificationCenter: notificationCenter,
            requestsCoordinator: requestsCoordinator
        )
    }
}

// MARK: - Shared error type

enum MediaRequestError: LocalizedError {
    case noRequestableSeasons

    var errorDescription: String? {
        switch self {
        case .noRequestableSeasons:
            "There are no requestable seasons for that quality."
        }
    }
}

// MARK: - Helpers

extension SeerrMediaItem {
    /// True when at least one request action (HD or 4K) would be shown.
    var hasRequestContextActions: Bool {
        mediaType != "person" &&
        ((mediaInfo?.isAvailable != true && mediaInfo?.hasHDRequest != true) || mediaInfo?.has4KRequest != true)
    }
}

extension SeerrTVDetail {
    func requestableSeasonNumbers(is4k: Bool) -> [Int] {
        requestableSeasons
            .map(\.seasonNumber)
            .filter { !isSeasonUnavailableForRequest($0, is4k: is4k) }
            .sorted()
    }

    func isSeasonUnavailableForRequest(_ seasonNumber: Int, is4k: Bool) -> Bool {
        guard let mediaInfo else { return false }

        if let seasonStatus = mediaInfo.seasons?.first(where: { $0.seasonNumber == seasonNumber }),
           seasonStatus.mediaStatus == .available || seasonStatus.mediaStatus == .processing {
            return true
        }

        return mediaInfo.requests?.contains { request in
            guard request.is4k == is4k,
                  let seasons = request.seasons else {
                return false
            }
            return seasons.contains { $0.seasonNumber == seasonNumber && $0.requestStatus != .declined }
        } == true
    }
}

#if DEBUG && os(iOS)
#Preview("Media Request Actions — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    VStack(alignment: .leading, spacing: 18) {
        Text("Request options")
            .font(.headline)

        MediaRequestContextMenu(
            mediaType: "movie",
            tmdbId: 550,
            title: "Fight Club",
            mediaInfo: nil,
            isKnownAvailable: false,
            apiClient: PreviewSupport.apiClient,
            notificationCenter: PreviewSupport.notificationCenter,
            requestsCoordinator: PreviewSupport.requestsCoordinator
        )
    }
    .padding(24)
    .frame(maxWidth: 360, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .padding()
}
#endif
