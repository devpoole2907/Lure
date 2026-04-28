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
        if #available(iOS 26.0, *) {
            List {
                librarySections(sections)
            }
            .listSectionIndexVisibility(.visible)
        } else {
            List {
                librarySections(sections)
            }
        }
    }

    @ViewBuilder
    private func librarySections(_ sections: [LibrarySection]) -> some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        LibraryListRow(item: item)
                    }
                }
            }
            .modifier(SectionIndexModifier(label: section.indexLabel))
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

private struct LibraryListRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.posterURL, width: 50, height: 75, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let year = item.year {
                        Text(year)
                    }
                    if item.mediaType == "tv" {
                        Text("• TV Series")
                    }
                    if let rating = item.voteAverage, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SectionIndexModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.sectionIndexLabel(Text(label))
        } else {
            content
        }
    }
}
