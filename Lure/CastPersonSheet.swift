import SwiftUI
import Observation

@Observable
final class CastPersonSheetViewModel {
    private(set) var person: SeerrPersonDetail?
    private(set) var credits: [SeerrMediaItem] = []
    private(set) var isLoading = false
    var error: String?

    let fallbackName: String?
    let fallbackProfileURL: URL?

    private let personId: Int?
    private let apiClient: SeerrAPIClient

    init(personId: Int?, fallbackName: String?, fallbackProfileURL: URL?, apiClient: SeerrAPIClient) {
        self.personId = personId
        self.fallbackName = fallbackName
        self.fallbackProfileURL = fallbackProfileURL
        self.apiClient = apiClient
    }

    func load() async {
        guard let personId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let detailLoad = apiClient.getPersonDetail(personId: personId)
            async let creditsLoad = apiClient.getPersonCombinedCredits(personId: personId)
            let (detail, combinedCredits) = try await (detailLoad, creditsLoad)

            person = detail

            var seenIDs = Set<String>()
            let orderedCredits = (combinedCredits.cast ?? []) + (combinedCredits.crew ?? [])
            credits = orderedCredits.compactMap { credit in
                guard let item = credit.toMediaItem() else { return nil }
                if seenIDs.insert(item.id).inserted {
                    return item
                }
                return nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum CastPersonPresentation: Equatable {
    case sheet
    case detail
}

struct CastPersonRoute: Identifiable, Hashable {
    let personId: Int?
    let fallbackName: String?
    let fallbackProfileURL: URL?

    var id: String {
        if let personId {
            return "person-\(personId)"
        }
        return "person-\(fallbackName ?? "unknown")-\(fallbackProfileURL?.absoluteString ?? "no-profile")"
    }

    init(personId: Int?, fallbackName: String?, fallbackProfileURL: URL?) {
        self.personId = personId
        self.fallbackName = fallbackName
        self.fallbackProfileURL = fallbackProfileURL
    }

    init(member: SeerrCastMember) {
        self.init(
            personId: member.id,
            fallbackName: member.name,
            fallbackProfileURL: member.profileURL
        )
    }
}

struct CastPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinService.self) private var jellyfinService
    let apiClient: SeerrAPIClient
    let presentation: CastPersonPresentation

    @State private var vm: CastPersonSheetViewModel
    @State private var libraryIDs: Set<String> = []
    #if os(tvOS)
    @State private var isBiographyExpanded = false
    #endif

    init(
        personId: Int?,
        fallbackName: String?,
        fallbackProfileURL: URL?,
        apiClient: SeerrAPIClient,
        presentation: CastPersonPresentation = .sheet
    ) {
        self.apiClient = apiClient
        self.presentation = presentation
        self._vm = State(initialValue: CastPersonSheetViewModel(
            personId: personId,
            fallbackName: fallbackName,
            fallbackProfileURL: fallbackProfileURL,
            apiClient: apiClient
        ))
    }

    var body: some View {
        Group {
            if presentation == .sheet {
                NavigationStack {
                    content
                }
                .navigationDestination(for: MediaDestination.self) { destination in
                    mediaDestinationView(destination)
                }
            } else {
                content
            }
        }
        #if os(tvOS)
        .castPersonModalFrame(isModal: presentation == .sheet)
        #endif
        #if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            await vm.load()
            libraryIDs = await jellyfinService.libraryMediaIDs()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                header

                biographySection

                let inLibrary = inLibraryCredits
                let other = otherCredits

                if !inLibrary.isEmpty {
                    MediaSliderView(
                        title: "In Your Library",
                        icon: "checkmark.circle",
                        items: inLibrary,
                        apiClient: apiClient,
                        extendsBeyondParentPadding: false
                    )
                }
                if !other.isEmpty {
                    MediaSliderView(
                        title: inLibrary.isEmpty ? nil : "More",
                        items: other,
                        apiClient: apiClient,
                        extendsBeyondParentPadding: false
                    )
                }
            }
            .padding(contentInsets)
        }
        .lureNavigationTitle(vm.person?.name ?? vm.fallbackName ?? "Cast")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .automatic) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaDestinationView(_ destination: MediaDestination) -> some View {
        if destination.mediaType == "movie" {
            MovieDetailView(
                tmdbId: destination.tmdbId,
                apiClient: apiClient,
                jellyfinService: jellyfinService,
                initialTitle: destination.title,
                initialPosterURL: destination.posterURL
            )
        } else {
            TVDetailView(
                tmdbId: destination.tmdbId,
                apiClient: apiClient,
                jellyfinService: jellyfinService,
                initialTitle: destination.title,
                initialPosterURL: destination.posterURL
            )
        }
    }

    private var inLibraryCredits: [SeerrMediaItem] {
        guard !libraryIDs.isEmpty else { return [] }
        return vm.credits.filter { libraryIDs.contains($0.id) }
    }

    private var otherCredits: [SeerrMediaItem] {
        guard !libraryIDs.isEmpty else { return vm.credits }
        return vm.credits.filter { !libraryIDs.contains($0.id) }
    }

    private var contentSpacing: CGFloat {
        #if os(tvOS)
        30
        #else
        20
        #endif
    }

    private var contentInsets: EdgeInsets {
        #if os(tvOS)
        if presentation == .detail {
            EdgeInsets(top: 70, leading: 90, bottom: 90, trailing: 90)
        } else {
            EdgeInsets(top: 56, leading: 56, bottom: 56, trailing: 56)
        }
        #else
        EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        #endif
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: headerSpacing) {
            PosterImage(
                url: vm.person?.profileURL ?? vm.fallbackProfileURL,
                width: profileWidth,
                height: profileHeight,
                cornerRadius: profileCornerRadius
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(vm.person?.name ?? vm.fallbackName ?? "Unknown")
                    .font(headerTitleFont)

                if let department = vm.person?.knownForDepartment, !department.isEmpty {
                    Label(department, systemImage: "sparkles")
                        .font(headerMetaFont)
                        .foregroundStyle(.secondary)
                }

                if let birthplace = vm.person?.placeOfBirth, !birthplace.isEmpty {
                    Label(birthplace, systemImage: "mappin.and.ellipse")
                        .font(headerMetaFont)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var biographySection: some View {
        if let biography = vm.person?.biography, !biography.isEmpty {
            #if os(tvOS)
            let showsToggle = shouldShowBiographyToggle(for: biography)
            VStack(alignment: .leading, spacing: 12) {
                Text("Biography")
                    .font(.title3.bold())

                Text(biography)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isBiographyExpanded || !showsToggle ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)

                if showsToggle {
                    OverviewToggleButton(title: isBiographyExpanded ? "LESS" : "MORE") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBiographyExpanded.toggle()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
            // The card must contain something focusable so the Siri Remote can
            // scroll the page back up to the biography/header. Long bios get the
            // MORE/LESS pill; short ones make the card itself focusable.
            .focusable(!showsToggle)
            // Focus section: swiping up from anywhere in the credit shelves
            // funnels focus to the pill. Without it the upward focus search
            // from a horizontally distant shelf card misses the small pill
            // entirely and focus gets stuck in the shelves.
            .focusSection()
            #else
            if shouldShowFullBiographyLink(for: biography) {
                NavigationLink {
                    BiographyDetailView(
                        title: vm.person?.name ?? vm.fallbackName ?? "Biography",
                        biography: biography
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Biography")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(biography)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Biography")
                        .font(.headline)
                    Text(biography)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
    }

    private var headerSpacing: CGFloat {
        #if os(tvOS)
        28
        #else
        16
        #endif
    }

    private var profileWidth: CGFloat {
        #if os(tvOS)
        136
        #else
        96
        #endif
    }

    private var profileHeight: CGFloat {
        #if os(tvOS)
        204
        #else
        144
        #endif
    }

    private var profileCornerRadius: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }

    private var headerTitleFont: Font {
        #if os(tvOS)
        .title.bold()
        #else
        .title3.weight(.bold)
        #endif
    }

    private var headerMetaFont: Font {
        #if os(tvOS)
        .body
        #else
        .subheadline
        #endif
    }

    private func shouldShowFullBiographyLink(for biography: String) -> Bool {
        biography.count > 280 || biography.contains("\n")
    }

    #if os(tvOS)
    /// Long bios collapse to a few lines behind a MORE/LESS pill — full-length
    /// Wikipedia bios otherwise dominate the screen and strand remote focus.
    private func shouldShowBiographyToggle(for biography: String) -> Bool {
        biography.count > 400
    }
    #endif
}

#if os(tvOS)
private extension View {
    @ViewBuilder
    func castPersonModalFrame(isModal: Bool) -> some View {
        if isModal {
            frame(width: 1180, height: 820)
                .background(.regularMaterial)
        } else {
            frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
        }
    }
}
#endif

private struct BiographyDetailView: View {
    let title: String
    let biography: String

    var body: some View {
        ScrollView {
            Text(biography)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .lureNavigationTitle(title)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
