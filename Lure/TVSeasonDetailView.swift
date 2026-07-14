import SwiftUI

struct TVSeasonDetailView: View {
    let show: SeerrTVDetail
    let season: SeerrTVSeason
    let statusSeason: SeerrSeasonStatus?

    private var seasonTitle: String {
        season.name ?? "Season \(season.seasonNumber)"
    }

    private var availableEpisodes: [SeerrEpisodeStatus] {
        statusSeason?.episodes ?? []
    }

    private var totalCount: Int { season.episodeCount ?? availableEpisodes.count }

    private var availableCount: Int {
        if let episodes = statusSeason?.episodes, !episodes.isEmpty {
            return episodes.filter { $0.status == 5 }.count
        }
        if statusSeason?.status == 5, totalCount > 0 {
            return totalCount
        }
        return 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                heroSection
                if totalCount > 0 || !availableEpisodes.isEmpty {
                    episodesCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .environment(\.colorScheme, .dark)
        .background { artBackground }
        .lureNavigationTitle(seasonTitle)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
    }

    // MARK: - Background

    private var artBackground: some View {
        AsyncImage(
            url: season.posterURL ?? show.posterURL,
            transaction: Transaction(animation: .easeInOut(duration: 0.3))
        ) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            default:
                Rectangle().fill(Color.purple.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(1.4)
        .blur(radius: 60)
        .saturation(1.6)
        .overlay(Color.black.opacity(0.55))
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            PosterImage(
                url: season.posterURL ?? show.posterURL,
                width: 160, height: 240, cornerRadius: 16
            )
            .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

            VStack(spacing: 6) {
                Text(seasonTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(show.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                if totalCount > 0 {
                    let allAvailable = availableCount == totalCount
                    let hasEpisodeData = statusSeason?.episodes != nil && !(statusSeason?.episodes?.isEmpty ?? true)
                    availabilityLabel(allAvailable: allAvailable, hasEpisodeData: hasEpisodeData)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(availabilityColor(allAvailable: allAvailable, hasEpisodeData: hasEpisodeData))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Episodes Card

    private var episodesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Episodes", systemImage: "list.bullet")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if totalCount > 0 {
                let fallbackAvailable = availableEpisodes.isEmpty && statusSeason?.status == 5
                ForEach(1...totalCount, id: \.self) { num in
                    let epStatus = availableEpisodes.first { $0.episodeNumber == num }
                    let status = epStatus ?? (fallbackAvailable ? SeerrEpisodeStatus(id: nil, episodeNumber: num, status: 5) : nil)
                    episodeRow(number: num, status: status, isLast: num == totalCount)
                }
            } else {
                let sorted = availableEpisodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
                ForEach(Array(sorted.enumerated()), id: \.offset) { idx, ep in
                    episodeRow(number: ep.episodeNumber ?? idx + 1, status: ep, isLast: idx == sorted.count - 1)
                }
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func availabilityLabel(allAvailable: Bool, hasEpisodeData: Bool) -> some View {
        let text: String
        let systemImage: String

        if hasEpisodeData {
            text = allAvailable ? "All Available" : "\(availableCount) of \(totalCount) available"
            systemImage = allAvailable ? "checkmark.circle.fill" : "circle.lefthalf.filled"
        } else if statusSeason?.status == 5 {
            text = "All \(totalCount) Available"
            systemImage = "checkmark.circle.fill"
        } else {
            text = "\(totalCount) episode\(totalCount == 1 ? "" : "s")"
            systemImage = "tv"
        }

        return HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
    }

    private func availabilityColor(allAvailable: Bool, hasEpisodeData: Bool) -> Color {
        if hasEpisodeData {
            return allAvailable ? .green : .purple
        }
        return statusSeason?.status == 5 ? .green : .secondary
    }

    private func episodeRow(number: Int, status: SeerrEpisodeStatus?, isLast: Bool) -> some View {
        let mediaStatus = status.flatMap { LureConstants.MediaStatus(rawValue: $0.status ?? -1) }

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(format: "E%02d", number))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                    .monospacedDigit()

                Text("Episode \(number)")
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                episodeStatusView(mediaStatus)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !isLast {
                Divider().padding(.leading, 58)
            }
        }
    }

    @ViewBuilder
    private func episodeStatusView(_ status: LureConstants.MediaStatus?) -> some View {
        if let status {
            switch status {
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .pending, .processing:
                Text(status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.2))
                    .clipShape(Capsule())
            case .partiallyAvailable:
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.yellow)
            case .deleted:
                Image(systemName: "trash.circle")
                    .foregroundStyle(.red)
            case .unknown:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        } else {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary.opacity(0.4))
        }
    }
}

extension SeerrTVSeason {
    var posterURL: URL? { ImageURL.poster(posterPath) }
}
