import SwiftUI

struct AdminDashboardCard: View {
    let requestCount: SeerrRequestCount?
    let apiClient: SeerrAPIClient

    var body: some View {
        VStack(alignment: .leading, spacing: LureDesign.Spacing.card) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Admin Dashboard")
                        .font(.headline)
                    Text("Approvals, queue health, and user access")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                pendingBadge
            }

            HStack(spacing: LureDesign.Spacing.row) {
                statBlock(title: "Total", value: requestCount?.total ?? 0)
                statBlock(title: "Movies", value: requestCount?.movie ?? 0)
                statBlock(title: "TV", value: requestCount?.tv ?? 0)
            }

            if let pending = requestCount?.pending {
                Text(pending == 1 ? "1 request is waiting for approval." : "\(pending) requests are waiting for approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                AdminUserManagementView(apiClient: apiClient)
            } label: {
                HStack {
                    Label("Manage Users", systemImage: "person.2.badge.gearshape")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(LureDesign.Spacing.card)
        .lureCard(radius: LureDesign.CornerRadius.card)
    }

    private var pendingBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(requestCount?.pending ?? 0)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text("Pending")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(LureDesign.Opacity.iconBackground), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.orange)
    }

    private func statBlock(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
