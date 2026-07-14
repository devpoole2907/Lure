import SwiftUI

struct StatusBadge: View {
    let mediaInfo: SeerrMediaInfo?

    var body: some View {
        if let status = mediaInfo?.mediaStatus, status.isUserVisible {
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
}

struct StatusOverlay: View {
    let mediaInfo: SeerrMediaInfo?

    var body: some View {
        if let status = mediaInfo?.mediaStatus, status != .unknown {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: status.systemImage)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(status.color)
                        .clipShape(Circle())
                        .padding(6)
                }
                Spacer()
            }
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Status Badges — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    VStack(spacing: 24) {
        StatusBadge(mediaInfo: PreviewSupport.previewMovieDetail.mediaInfo)

        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(width: 180, height: 270)
            StatusOverlay(mediaInfo: PreviewSupport.previewMovieDetail.mediaInfo)
        }
    }
    .padding()
}
#endif
