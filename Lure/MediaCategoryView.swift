import SwiftUI

struct MediaCategoryView: View {
    let title: String
    let items: [LibraryItem]
    let apiClient: SeerrAPIClient
    var initialSortOrder: LibrarySortOrder = .title

    @State private var sortOrder: LibrarySortOrder
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    init(title: String, items: [LibraryItem], apiClient: SeerrAPIClient, initialSortOrder: LibrarySortOrder = .title) {
        self.title = title
        self.items = items
        self.apiClient = apiClient
        self.initialSortOrder = initialSortOrder
        self._sortOrder = State(initialValue: initialSortOrder)
    }

    private var sorted: [LibraryItem] {
        switch sortOrder {
        case .title:  items.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .year:   items.sorted { ($0.year ?? "") > ($1.year ?? "") }
        case .rating: items.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        case .added:  items.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        }
    }

    private var sections: [LibrarySection] {
        guard sortOrder == .title else {
            return [LibrarySection(title: sortOrder.rawValue, indexLabel: "", items: sorted)]
        }
        let grouped = Dictionary(grouping: sorted) { sectionLabel(for: $0.title) }
        return grouped.keys.sorted().map { label in
            LibrarySection(title: label, indexLabel: label, items: grouped[label] ?? [])
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing Here",
                    systemImage: "film",
                    description: Text("No \(title.lowercased()) are currently available.")
                )
            } else {
#if os(iOS)
                if #available(iOS 26.0, *), sortOrder == .title {
                    List { listContent }
                        .listSectionIndexVisibility(.visible)
                } else {
                    List { listContent }
                }
#else
                List { listContent }
#endif
            }
        }
        .lureNavigationTitle(title)
#if os(iOS) || os(visionOS)
        .toolbarTitleDisplayMode(.large)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Button {
                            withAnimation { sortOrder = order }
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        MediaListRow(item: item)
                    }
                    .contextMenu {
                        LibraryItemRequestContextMenu(
                            item: item,
                            apiClient: apiClient,
                            notificationCenter: notificationCenter,
                            requestsCoordinator: requestsCoordinator
                        )
                    }
                }
            }
            .modifier(SectionIndexLabel(label: section.indexLabel, active: sortOrder == .title))
        }
    }

    private func destination(for item: LibraryItem) -> MediaDestination {
        MediaDestination(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            posterURL: item.posterURL
        )
    }

    private func sectionLabel(for title: String) -> String {
        guard let scalar = title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else {
            return "#"
        }
        let label = String(scalar).uppercased()
        return label.range(of: "[A-Z]", options: .regularExpression) != nil ? label : "#"
    }
}

private struct SectionIndexLabel: ViewModifier {
    let label: String
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), active {
            content.sectionIndexLabel(Text(label))
        } else {
            content
        }
    }
}
