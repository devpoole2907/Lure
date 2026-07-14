import SwiftUI

struct TitleCardView: View {
    let item: SeerrMediaItem
    var certification: String? = nil
    #if os(tvOS)
    var posterWidth: CGFloat = 260
    var posterHeight: CGFloat = 390
    #else
    var posterWidth: CGFloat = 140
    var posterHeight: CGFloat = 210
    #endif

    private var cornerRadius: CGFloat { posterWidth * 0.086 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PosterImage(url: item.posterURL, width: posterWidth, height: posterHeight, cornerRadius: cornerRadius)

                if let mediaInfo = item.mediaInfo {
                    StatusOverlay(mediaInfo: mediaInfo)
                }
            }
            .frame(width: posterWidth, height: posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            captionBlock
        }
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                #if os(tvOS)
                .font(.callout.weight(.medium))
                #else
                .font(.caption.weight(.medium))
                #endif
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                if let cert = certification {
                    Text(cert)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(.secondary.opacity(0.5), lineWidth: 1)
                        )
                }
                if let year = item.year {
                    Text(year)
                }
                if let rating = item.voteAverage, rating > 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(width: posterWidth, alignment: .leading)
        .padding(.top, 6)
        .padding(.horizontal, 2)
    }
}
