import SwiftUI

struct LibraryContentView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("Loading Library...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            ContentUnavailableView(
                "Library Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Nothing Available",
                systemImage: "film",
                description: Text("No media is currently available on your server.")
            )
        } else {
            LibraryListView(viewModel: viewModel)
        }
    }
}

private struct LibraryListView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        let sections = viewModel.sectionedItems
#if os(iOS)
        if #available(iOS 26.0, *), viewModel.isIndexed {
            List {
                librarySections(sections)
            }
            .listSectionIndexVisibility(.visible)
        } else {
            List {
                librarySections(sections)
            }
        }
#else
        List {
            librarySections(sections)
        }
#endif
    }

    @ViewBuilder
    private func librarySections(_ sections: [LibrarySection]) -> some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        MediaListRow(item: item)
                    }
                }
            }
            .modifier(SectionIndexModifier(label: section.indexLabel, isIndexed: viewModel.isIndexed))
        }

        if viewModel.isRefreshing {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
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
}

private struct SectionIndexModifier: ViewModifier {
    let label: String
    let isIndexed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isIndexed {
            content.sectionIndexLabel(Text(label))
        } else {
            content
        }
    }
}
