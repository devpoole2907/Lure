import SwiftUI

struct TitleCardView: View {
    let item: SeerrMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PosterImage(url: item.posterURL, width: 140, height: 210, cornerRadius: 12)
                
                // StatusBadge goes here instead of overlay checkmark, similar to Trawl but adapted for Lure
                if let mediaInfo = item.mediaInfo {
                    StatusOverlay(mediaInfo: mediaInfo)
                }
            }
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
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
            .frame(width: 140, alignment: .leading)
            .padding(.top, 6)
            .padding(.horizontal, 2)
        }
    }
}