import SwiftUI

struct TVDetailView: View {
    let tmdbId: Int
    let apiClient: SeerrAPIClient
    let initialTitle: String?
    let initialPosterURL: URL?

    @State private var vm: TVDetailViewModel
    @State private var showRequestSheet = false
    @State private var showReportSheet = false
    @State private var selectedCastMember: SeerrCastMember?
    @Environment(InAppNotificationCenter.self) private var notificationCenter

    init(tmdbId: Int, apiClient: SeerrAPIClient, initialTitle: String? = nil, initialPosterURL: URL? = nil) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
        self.initialTitle = initialTitle
        self.initialPosterURL = initialPosterURL
        self._vm = State(initialValue: TVDetailViewModel(tmdbId: tmdbId, apiClient: apiClient))
    }

    var body: some View {
        Group {
            if let show = vm.show {
                scrollContent(show)
                    .background { artBackground(url: show.posterURL) }
                    .transition(.opacity)
            } else if vm.isLoading {
                loadingContent
                    .transition(.opacity)
            } else {
                ContentUnavailableView("Show Not Found", systemImage: "tv")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.show?.id)
        .animation(.easeInOut(duration: 0.25), value: vm.ratings != nil)
        .animation(.easeInOut(duration: 0.25), value: vm.recommendations.count)
        .navigationTitle(vm.show?.displayTitle ?? initialTitle ?? "TV Show")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("Report an Issue", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportIssueSheet(
                mediaId: vm.show?.mediaInfo?.id,
                mediaTitle: vm.show?.displayTitle ?? initialTitle,
                apiClient: apiClient
            )
        }
        .errorAlert(item: Binding(
            get: { vm.error.map { ErrorAlertItem(title: "Error", message: $0) } },
            set: { _ in vm.error = nil }
        ))
        .sheet(isPresented: $showRequestSheet) {
            TVRequestSheet(viewModel: vm)
        }
        .sheet(item: $selectedCastMember) { member in
            CastPersonSheet(
                personId: member.id,
                fallbackName: member.name,
                fallbackProfileURL: member.profileURL,
                apiClient: apiClient
            )
        }
        .task { await vm.load() }
        .onChange(of: vm.requestSuccess) { _, success in
            if success {
                notificationCenter.show(LureBannerItem(
                    title: "Request Submitted",
                    message: vm.show?.displayTitle ?? initialTitle,
                    style: .success
                ))
            }
        }
        .onChange(of: vm.error) { _, error in
            if let error {
                notificationCenter.show(LureBannerItem(
                    title: "Request Failed",
                    message: error,
                    style: .error
                ))
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var loadingContent: some View {
        if let initialPosterURL {
            VStack(spacing: 18) {
                PosterImage(url: initialPosterURL, width: 160, height: 240, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                ProgressView("Loading...")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { artBackground(url: initialPosterURL) }
        } else {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artBackground(url: URL?) -> some View {
        AsyncImage(
            url: url,
            transaction: Transaction(animation: .easeInOut(duration: 0.3))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure, .empty:
                Rectangle().fill(Color.purple.opacity(0.4))
            @unknown default:
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

    // MARK: - Scroll Content

    private func scrollContent(_ show: SeerrTVDetail) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                heroSection(show)
                cardsSection(show)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Hero

    private func heroSection(_ show: SeerrTVDetail) -> some View {
        VStack(spacing: 14) {
            PosterImage(url: show.posterURL, width: 160, height: 240, cornerRadius: 16)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

            VStack(spacing: 6) {
                Text(show.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let cert = show.contentRatingText {
                        Text(cert)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                    if let year = show.year { Text(year) }
                    if let seasons = show.numberOfSeasons {
                        Text("·")
                        Text(seasons == 1 ? "1 season" : "\(seasons) seasons")
                    }
                    if let network = show.networks?.first?.name {
                        Text("·")
                        Text(network)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if let status = show.mediaInfo?.mediaStatus, status.isUserVisible {
                    pill(icon: status.systemImage, label: status.displayName, color: status.color)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Cards Section

    @ViewBuilder
    private func cardsSection(_ show: SeerrTVDetail) -> some View {
        requestCard(show)

        if let overview = show.overview, !overview.isEmpty {
            overviewCard(overview)
        }

        statsCard(show)

        if !show.requestableSeasons.isEmpty {
            ForEach(show.requestableSeasons) { season in
                let statusSeason = show.mediaInfo?.seasons?.first { $0.seasonNumber == season.seasonNumber }
                seasonNavCard(show: show, season: season, statusSeason: statusSeason)
            }
        }

        if let providers = show.usWatchProviders, !(providers.flatrate ?? []).isEmpty {
            watchProvidersCard(providers)
        }

        if let genres = show.genres, !genres.isEmpty {
            genreChips(genres.compactMap(\.name))
        }

        if let ratings = vm.ratings, ratings.hasAnyScore {
            ratingsCard(ratings)
        }

        if let cast = show.credits?.cast, !cast.isEmpty {
            castCard(Array(cast.prefix(20)))
        }

        if let url = show.trailerURL {
            trailerCard(url)
        }

        let infoRows = showInfoRows(show)
        if !infoRows.isEmpty {
            rowsCard(header: "Info", icon: "info.circle", rows: infoRows)
        }

        if !vm.recommendations.isEmpty {
            MediaSliderView(title: "You Might Also Like", icon: "sparkles", items: vm.recommendations, apiClient: apiClient)
        }    }

    // MARK: - Request Card

    @ViewBuilder
    private func requestCard(_ show: SeerrTVDetail) -> some View {
        if show.mediaInfo?.isAvailable == true {
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.tint(Color.green.opacity(0.2)), in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button { showRequestSheet = true } label: {
                Label(show.mediaInfo?.requestStatusLabel ?? "Request", systemImage: requestButtonIcon(for: show))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func requestButtonIcon(for show: SeerrTVDetail) -> String {
        show.mediaInfo?.isRequested == true ? "clock.fill" : "plus.circle.fill"
    }

    // MARK: - Overview Card

    private func overviewCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Overview", icon: "text.alignleft")
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Stats Card

    private func statsCard(_ show: SeerrTVDetail) -> some View {
        HStack(spacing: 0) {
            if let year = show.year {
                statCell(value: year, label: "Year")
                cardDivider
            }
            if let seasons = show.numberOfSeasons {
                statCell(value: "\(seasons)", label: seasons == 1 ? "Season" : "Seasons")
                cardDivider
            }
            statCell(
                value: shortShowStatus(show.status)
                    ?? show.mediaInfo?.requestStatusLabel
                    ?? (show.mediaInfo?.mediaStatus?.isUserVisible == true
                        ? show.mediaInfo?.mediaStatus?.displayName ?? "Not Requested"
                        : "Not Requested"),
                label: "Series Status"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Season Nav Card

    private func seasonNavCard(show: SeerrTVDetail, season: SeerrTVSeason, statusSeason: SeerrSeasonStatus?) -> some View {
        let availableCount = statusSeason?.episodes?.filter { $0.status == 5 }.count ?? 0
        let totalCount = season.episodeCount ?? 0
        let allAvailable = totalCount > 0 && availableCount == totalCount

        return NavigationLink {
            TVSeasonDetailView(show: show, season: season, statusSeason: statusSeason)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(season.name ?? "Season \(season.seasonNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(totalCount > 0 ? "\(availableCount) of \(totalCount) available" : "\(season.episodeCount ?? 0) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 48, height: 4)
                    if totalCount > 0 {
                        Capsule()
                            .fill(allAvailable ? Color.green : Color.purple)
                            .frame(width: 48 * CGFloat(availableCount) / CGFloat(totalCount), height: 4)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Watch Providers Card

    private func watchProvidersCard(_ providers: SeerrWatchProviders) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Streaming", icon: "play.tv")
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(providers.flatrate ?? [], id: \.stableID) { provider in
                        VStack(spacing: 4) {
                            AsyncImage(url: provider.logoURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(provider.providerName ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .horizontalSoftEdges()
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Genre Chips

    private func genreChips(_ genres: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres.prefix(8), id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
        .horizontalSoftEdges()
        .frame(maxWidth: .infinity)
    }

    private func shortShowStatus(_ status: String?) -> String? {
        switch status {
        case "Returning Series":
            return "Ongoing"
        case "Planned":
            return "Planned"
        case "Ended":
            return "Ended"
        case "Canceled":
            return "Canceled"
        default:
            return status
        }
    }

    // MARK: - Ratings Card

    private func ratingsCard(_ ratings: SeerrRatingsCombined) -> some View {
        let items: [(String, String)] = [
            ratings.imdbRating.map { ("IMDb", String(format: "%.1f", $0)) },
            ratings.tmdbRating.map { ("TMDb", String(format: "%.0f%%", $0 * 10)) },
            ratings.criticsScore.map { ("RT", "\($0)%") },
            ratings.audienceScore.map { ("Audience", "\($0)%") }
        ].compactMap { $0 }

        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                statCell(value: item.1, label: item.0)
                if index < items.count - 1 { cardDivider }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Cast Card

    private func castCard(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Cast", icon: "person.2")
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cast) { member in
                        Button {
                            selectedCastMember = member
                        } label: {
                            VStack(spacing: 4) {
                                AsyncImage(url: member.profileURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(.quaternary)
                                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())

                                Text(member.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 70)
                                Text(member.character ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .horizontalSoftEdges()
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Trailer Card

    private func trailerCard(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Trailer")
                        .font(.subheadline.weight(.semibold))
                    Text("Opens YouTube")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Rows Data

    private func showInfoRows(_ show: SeerrTVDetail) -> [(String, String, String)] {
        var rows: [(String, String, String)] = []
        if let type = show.type {
            rows.append(("list.bullet", "Type", type))
        }
        if let network = show.networks?.first?.name {
            rows.append(("antenna.radiowaves.left.and.right", "Network", network))
        }
        if let episodes = show.numberOfEpisodes {
            rows.append(("play.rectangle.on.rectangle", "Episodes", "\(episodes)"))
        }
        if let runtime = show.episodeRunTime?.first, runtime > 0 {
            rows.append(("clock", "Runtime", "\(runtime)m / episode"))
        }
        if let lang = show.originalLanguage, !lang.isEmpty {
            rows.append(("globe", "Language", lang.uppercased()))
        }
        return rows
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private var cardDivider: some View {
        Rectangle().fill(.separator).frame(width: 0.5, height: 26)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(icon: String, label: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: Capsule())
    }

    private func rowsCard(header: String, icon: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(header, icon: icon)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .center)
                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.2)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if index < rows.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - TV Request Sheet

struct TVRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: TVDetailViewModel
    @State private var requestIn4K = false

    private var seasons: [SeerrTVSeason] {
        viewModel.show?.requestableSeasons ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        actionPill("Select All", systemImage: "checkmark.circle") {
                            viewModel.selectAllSeasons(is4k: requestIn4K)
                        }

                        actionPill("Clear", systemImage: "xmark.circle") {
                            viewModel.deselectAllSeasons()
                        }

                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Select Seasons")
                }

                Section {
                    ForEach(seasons) { season in
                        let unavailable = viewModel.isSeasonUnavailableForRequest(season.seasonNumber, is4k: requestIn4K)

                        Button {
                            if !unavailable { viewModel.toggleSeason(season.seasonNumber) }
                        } label: {
                            HStack {
                                Image(systemName: viewModel.selectedSeasons.contains(season.seasonNumber) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(unavailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

                                Text(season.name ?? "Season \(season.seasonNumber)")
                                    .foregroundStyle(unavailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                                Spacer()

                                if unavailable {
                                    Text(viewModel.unavailableSeasonReason(season.seasonNumber, is4k: requestIn4K) ?? "Unavailable")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(unavailable)
                    }
                }

                Section("Options") {
                    Toggle(isOn: $requestIn4K) {
                        Label("Request in 4K", systemImage: "sparkles.tv")
                    }
                }
            }
            .navigationTitle("Request Seasons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Request") {
                        Task {
                            await viewModel.requestShow(is4k: requestIn4K)
                            if viewModel.requestSuccess { dismiss() }
                        }
                    }
                    .disabled(viewModel.selectedSeasons.isEmpty || viewModel.isRequesting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: requestIn4K) { _, is4k in
            viewModel.filterSelectedSeasons(for: is4k)
        }
    }

    private func actionPill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
