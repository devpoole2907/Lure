import SwiftUI

struct MovieDetailView: View {
    let tmdbId: Int
    let apiClient: SeerrAPIClient
    let initialTitle: String?
    let initialPosterURL: URL?

    @State private var vm: MovieDetailViewModel
    @State private var showRequestOptions = false
    @State private var showReportSheet = false
    @State private var selectedCastMember: SeerrCastMember?
    @Environment(InAppNotificationCenter.self) private var notificationCenter

    init(tmdbId: Int, apiClient: SeerrAPIClient, initialTitle: String? = nil, initialPosterURL: URL? = nil) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
        self.initialTitle = initialTitle
        self.initialPosterURL = initialPosterURL
        self._vm = State(initialValue: MovieDetailViewModel(tmdbId: tmdbId, apiClient: apiClient))
    }

    var body: some View {
        Group {
            if let movie = vm.movie {
                scrollContent(movie)
                    .background { artBackground(url: movie.posterURL) }
                    .transition(.opacity)
            } else if vm.isLoading {
                loadingContent
                    .transition(.opacity)
            } else {
                ContentUnavailableView("Movie Not Found", systemImage: "film")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.movie?.id)
        .animation(.easeInOut(duration: 0.25), value: vm.ratings != nil)
        .animation(.easeInOut(duration: 0.25), value: vm.recommendations.count)
        .navigationTitle(vm.movie?.displayTitle ?? initialTitle ?? "Movie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
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
                mediaId: vm.movie?.mediaInfo?.id,
                mediaTitle: vm.movie?.displayTitle ?? initialTitle,
                apiClient: apiClient
            )
        }
        .errorAlert(item: Binding(
            get: { vm.error.map { ErrorAlertItem(title: "Error", message: $0) } },
            set: { _ in vm.error = nil }
        ))
        .sheet(item: $selectedCastMember) { member in
            CastPersonSheet(
                personId: member.id,
                fallbackName: member.name,
                fallbackProfileURL: member.profileURL,
                apiClient: apiClient
            )
        }
        .alert("Request Movie", isPresented: $showRequestOptions) {
            Button("Request HD") {
                Task { await vm.requestMovie(is4k: false) }
            }
            .disabled(vm.movie?.mediaInfo?.hasHDRequest == true || vm.isRequesting)
            Button("Request 4K") {
                Task { await vm.requestMovie(is4k: true) }
            }
            .disabled(vm.movie?.mediaInfo?.has4KRequest == true || vm.isRequesting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the quality for this request.")
        }
        .task { await vm.load() }
        .onChange(of: vm.requestSuccess) { _, success in
            if success {
                notificationCenter.show(LureBannerItem(
                    title: "Request Submitted",
                    message: vm.movie?.displayTitle ?? initialTitle,
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
                Rectangle().fill(Color.indigo.opacity(0.4))
            @unknown default:
                Rectangle().fill(Color.indigo.opacity(0.4))
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

    private func scrollContent(_ movie: SeerrMovieDetail) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                heroSection(movie)
                cardsSection(movie)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Hero

    private func heroSection(_ movie: SeerrMovieDetail) -> some View {
        VStack(spacing: 14) {
            PosterImage(url: movie.posterURL, width: 160, height: 240, cornerRadius: 16)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

            VStack(spacing: 6) {
                Text(movie.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let cert = movie.certificationText {
                        Text(cert)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                    if let year = movie.year { Text(year) }
                    if let runtime = movie.runtime, runtime > 0 { Text("·"); Text("\(runtime)m") }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if let status = movie.mediaInfo?.mediaStatus, status.isUserVisible {
                    pill(icon: status.systemImage, label: status.displayName, color: status.color)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Cards Section

    @ViewBuilder
    private func cardsSection(_ movie: SeerrMovieDetail) -> some View {
        requestCard(movie)

        if let overview = movie.overview, !overview.isEmpty {
            overviewCard(overview)
        }

        statsCard(movie)

        if let providers = movie.usWatchProviders, !(providers.flatrate ?? []).isEmpty {
            watchProvidersCard(providers)
        }

        if let genres = movie.genres, !genres.isEmpty {
            genreChips(genres.compactMap(\.name))
        }

        if let ratings = vm.ratings, ratings.hasAnyScore {
            ratingsCard(ratings)
        }

        if let cast = movie.credits?.cast, !cast.isEmpty {
            castCard(Array(cast.prefix(20)))
        }

        if let url = movie.trailerURL {
            trailerCard(url)
        }

        let infoRows = movieInfoRows(movie)
        if !infoRows.isEmpty {
            rowsCard(header: "Info", icon: "info.circle", rows: infoRows)
        }
// Recommendations
if !vm.recommendations.isEmpty {
    MediaSliderView(title: "You Might Also Like", icon: "sparkles", items: vm.recommendations, apiClient: apiClient)
}
    }

    // MARK: - Request Card

    @ViewBuilder
    private func requestCard(_ movie: SeerrMovieDetail) -> some View {
        if movie.mediaInfo?.isAvailable == true {
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.tint(Color.green.opacity(0.2)), in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button {
                showRequestOptions = true
            } label: {
                Group {
                    if vm.isRequesting {
                        ProgressView()
                    } else {
                        Label(movie.mediaInfo?.requestStatusLabel ?? "Request", systemImage: requestButtonIcon(for: movie))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            .disabled(vm.isRequesting)
        }
    }

    private func requestButtonIcon(for movie: SeerrMovieDetail) -> String {
        movie.mediaInfo?.isRequested == true ? "clock.fill" : "plus.circle.fill"
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

    private func statsCard(_ movie: SeerrMovieDetail) -> some View {
        HStack(spacing: 0) {
            if let year = movie.year {
                statCell(value: year, label: "Year")
                cardDivider
            }
            if let runtime = movie.runtime, runtime > 0 {
                statCell(value: "\(runtime)m", label: "Runtime")
                cardDivider
            }
            statCell(
                value: movie.mediaInfo?.requestStatusLabel
                    ?? (movie.mediaInfo?.mediaStatus?.isUserVisible == true
                        ? movie.mediaInfo?.mediaStatus?.displayName ?? "Not Requested"
                        : "Not Requested"),
                label: "Status"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
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

    private func movieInfoRows(_ movie: SeerrMovieDetail) -> [(String, String, String)] {
        var rows: [(String, String, String)] = []
        if let availability = movie.releaseAvailabilityText {
            rows.append(("ticket", "Availability", availability))
        }
        if let status = movie.status {
            rows.append(("circle.fill", "Status", status))
        }
        if let studios = movie.productionCompanies, !studios.isEmpty {
            rows.append(("building.2", "Studio", studios.prefix(2).compactMap(\.name).joined(separator: ", ")))
        }
        if let budget = movie.budget, budget > 0 {
            rows.append(("dollarsign.circle", "Budget", "$\(budget / 1_000_000)M"))
        }
        if let revenue = movie.revenue, revenue > 0 {
            rows.append(("chart.bar.fill", "Revenue", "$\(revenue / 1_000_000)M"))
        }
        if let lang = movie.originalLanguage, !lang.isEmpty {
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
