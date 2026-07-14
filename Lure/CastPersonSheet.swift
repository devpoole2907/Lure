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

    private var personId: Int?
    private let apiClient: SeerrAPIClient

    init(personId: Int?, fallbackName: String?, fallbackProfileURL: URL?, apiClient: SeerrAPIClient) {
        self.personId = personId
        self.fallbackName = fallbackName
        self.fallbackProfileURL = fallbackProfileURL
        self.apiClient = apiClient
    }

    #if DEBUG
    init(previewPerson: SeerrPersonDetail, credits: [SeerrMediaItem], apiClient: SeerrAPIClient) {
        self.person = previewPerson
        self.credits = credits
        self.personId = previewPerson.id
        self.fallbackName = previewPerson.name
        self.fallbackProfileURL = previewPerson.profileURL
        self.apiClient = apiClient
    }
    #endif

    func load() async {
        // Jellyfin-sourced people (episode cast) have no TMDB id — resolve one
        // by name through Seerr search so the full bio and credits still load.
        if personId == nil {
            await resolvePersonIdByName()
        }
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

    private func resolvePersonIdByName() async {
        guard let name = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        guard let response = try? await apiClient.search(query: name, page: 1) else { return }
        let people = response.results.compactMap { result -> SeerrPersonResult? in
            if case .person(let person) = result.toMediaItem() { return person }
            return nil
        }
        // Prefer an exact (case-insensitive) name match; fall back to the top
        // person hit so common transliterations still resolve.
        let match = people.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame } ?? people.first
        personId = match?.id
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
    let onSelectMedia: ((MediaDestination) -> Void)?

    @State private var vm: CastPersonSheetViewModel
    @State private var libraryIDs: Set<String> = []
    #if os(tvOS)
    @State private var isBiographyExpanded = false
    @FocusState private var focusedContent: CastPersonFocusTarget?

    private enum CastPersonFocusTarget: Hashable {
        case identity
        case biography
        case biographyToggle
    }
    #endif

    init(
        personId: Int?,
        fallbackName: String?,
        fallbackProfileURL: URL?,
        apiClient: SeerrAPIClient,
        presentation: CastPersonPresentation = .sheet,
        onSelectMedia: ((MediaDestination) -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.presentation = presentation
        self.onSelectMedia = onSelectMedia
        self._vm = State(initialValue: CastPersonSheetViewModel(
            personId: personId,
            fallbackName: fallbackName,
            fallbackProfileURL: fallbackProfileURL,
            apiClient: apiClient
        ))
    }

    #if DEBUG
    init(
        previewPerson: SeerrPersonDetail,
        credits: [SeerrMediaItem],
        apiClient: SeerrAPIClient,
        presentation: CastPersonPresentation
    ) {
        self.apiClient = apiClient
        self.presentation = presentation
        self.onSelectMedia = nil
        self._vm = State(initialValue: CastPersonSheetViewModel(
            previewPerson: previewPerson,
            credits: credits,
            apiClient: apiClient
        ))
    }
    #endif

    var body: some View {
        Group {
            if presentation == .sheet {
                NavigationStack {
                    content
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
                        items: inLibrary,
                        apiClient: apiClient,
                        extendsBeyondParentPadding: false,
                        onSelect: openMediaDestination
                    )
                }
                if !other.isEmpty {
                    MediaSliderView(
                        title: inLibrary.isEmpty ? nil : "More",
                        items: other,
                        apiClient: apiClient,
                        extendsBeyondParentPadding: false,
                        onSelect: openMediaDestination
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

    private func openMediaDestination(_ destination: MediaDestination) {
        guard let onSelectMedia else { return }
        onSelectMedia(destination)
        dismiss()
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

            #if os(tvOS)
            Button(action: {}) {
                personIdentity
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedContent, equals: .identity)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(focusedContent == .identity ? .white.opacity(0.12) : .clear)
            }
            .scaleEffect(focusedContent == .identity ? 1.03 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.16), value: focusedContent == .identity)
            #else
            personIdentity
            #endif
            Spacer()
        }
    }

    private var personIdentity: some View {
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
    }

    @ViewBuilder
    private var biographySection: some View {
        if let biography = vm.person?.biography, !biography.isEmpty {
            #if os(tvOS)
            let showsToggle = shouldShowBiographyToggle(for: biography)
            VStack(alignment: .leading, spacing: 12) {
                Button(action: {}) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Biography")
                            .font(.title3.bold())

                        Text(biography)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isBiographyExpanded || !showsToggle ? nil : 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedContent, equals: .biography)

                if showsToggle {
                    OverviewToggleButton(title: isBiographyExpanded ? "LESS" : "MORE") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBiographyExpanded.toggle()
                        }
                    }
                    .focused($focusedContent, equals: .biographyToggle)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        focusedContent == .biography ? .white.opacity(0.7) : .clear,
                        lineWidth: 2
                    )
            }
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

#if DEBUG && os(iOS)
#Preview("Cast Person — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    CastPersonSheet(
        previewPerson: SeerrPersonDetail(
            id: 287,
            name: "Brad Pitt",
            biography: "An acclaimed actor and producer known for performances spanning character-driven dramas, thrillers, and large-scale studio films. His work has earned recognition both in front of and behind the camera.",
            birthday: "1963-12-18",
            deathday: nil,
            placeOfBirth: "Shawnee, Oklahoma, USA",
            knownForDepartment: "Acting",
            profilePath: nil
        ),
        credits: PreviewSupport.sampleItems,
        apiClient: PreviewSupport.apiClient,
        presentation: .sheet
    )
    .environment(PreviewSupport.jellyfinService)
}
#endif
