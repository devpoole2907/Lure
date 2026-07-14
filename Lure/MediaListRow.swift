import SwiftUI

struct MediaListRow: View {
    let posterURL: URL?
    let title: String
    let mediaType: String
    let year: String?
    let mediaStatus: LureConstants.MediaStatus?

    init(item: SeerrMediaItem) {
        self.posterURL = item.posterURL
        self.title = item.title
        self.mediaType = item.mediaType
        self.year = item.year
        if let info = item.mediaInfo, let status = info.mediaStatus, status.isUserVisible {
            self.mediaStatus = status
        } else {
            self.mediaStatus = nil
        }
    }

    init(item: LibraryItem) {
        self.posterURL = item.posterURL
        self.title = item.title
        self.mediaType = item.mediaType
        self.year = item.year
        self.mediaStatus = item.isAvailable ? .available : .partiallyAvailable
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: posterURL, width: 50, height: 75, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let label = mediaTypeLabel {
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }

                    if let year {
                        Text(year)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let status = mediaStatus {
                    HStack(spacing: 4) {
                        Image(systemName: status.systemImage)
                        Text(status.displayName)
                    }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.color.opacity(0.12))
                        .foregroundStyle(status.color)
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var mediaTypeLabel: String? {
        switch mediaType {
        case "tv":
            return "TV"
        case "movie":
            return "Movie"
        case "person":
            return "Person"
        default:
            return nil
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Media List Row — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    List {
        MediaListRow(
            item: PreviewSupport.movieItem(
                mediaInfo: PreviewSupport.previewMovieDetail.mediaInfo
            )
        )
        MediaListRow(item: PreviewSupport.tvItem())
    }
}
#endif
