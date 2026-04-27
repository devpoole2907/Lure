import SwiftUI

struct StatusBadge: View {
    let mediaInfo: SeerrMediaInfo?

    var body: some View {
        if let status = mediaInfo?.mediaStatus, status.isUserVisible {
            Label(status.displayName, systemImage: status.systemImage)
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
