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

struct CastPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinService.self) private var jellyfinService
    let apiClient: SeerrAPIClient

    @State private var vm: CastPersonSheetViewModel
    @State private var libraryIDs: Set<String> = []

    init(personId: Int?, fallbackName: String?, fallbackProfileURL: URL?, apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
        self._vm = State(initialValue: CastPersonSheetViewModel(
            personId: personId,
            fallbackName: fallbackName,
            fallbackProfileURL: fallbackProfileURL,
            apiClient: apiClient
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let biography = vm.person?.biography, !biography.isEmpty {
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
                    }

                    let inLibrary = inLibraryCredits
                    let other = otherCredits

                    if !inLibrary.isEmpty {
                        MediaSliderView(title: "In Your Library", icon: "checkmark.circle", items: inLibrary, apiClient: apiClient)
                    }
                    if !other.isEmpty {
                        MediaSliderView(title: inLibrary.isEmpty ? nil : "More", items: other, apiClient: apiClient)
                    }
                }
                .padding(16)
            }
            .navigationTitle(vm.person?.name ?? vm.fallbackName ?? "Cast")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationDestination(for: MediaDestination.self) { dest in
                if dest.mediaType == "movie" {
                    MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                } else {
                    TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                }
            }
        }
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
        .task {
            await vm.load()
            libraryIDs = await jellyfinService.libraryMediaIDs()
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

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(url: vm.person?.profileURL ?? vm.fallbackProfileURL, width: 96, height: 144, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(vm.person?.name ?? vm.fallbackName ?? "Unknown")
                    .font(.title3.weight(.bold))

                if let department = vm.person?.knownForDepartment, !department.isEmpty {
                    Label(department, systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let birthplace = vm.person?.placeOfBirth, !birthplace.isEmpty {
                    Label(birthplace, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func shouldShowFullBiographyLink(for biography: String) -> Bool {
        biography.count > 280 || biography.contains("\n")
    }
}

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
        .navigationTitle(title)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
