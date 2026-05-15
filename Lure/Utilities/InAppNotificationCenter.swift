import SwiftUI

@Observable
@MainActor
final class InAppNotificationCenter {
    var currentBanner: LureBannerItem?

    private static let autoDismissDelay: Duration = .seconds(4)
    private var dismissTask: Task<Void, Never>?

    func show(_ item: LureBannerItem) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            currentBanner = item
        }
        let id = item.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoDismissDelay)
            guard let self, !Task.isCancelled, currentBanner?.id == id else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentBanner = nil
        }
    }
}

struct LureBannerItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let style: LureBannerStyle

    enum LureBannerStyle {
        case success, error, info
    }
}

struct LureNotificationBanner: View {
    let item: LureBannerItem
    let onDismiss: () -> Void

    @State private var offsetY: CGFloat = 0

    private var tintColor: Color {
        switch item.style {
        case .success: .green
        case .error: .red
        case .info: .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let message = item.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.secondary)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(tintColor.opacity(0.18)), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
        .offset(y: offsetY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        offsetY = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        onDismiss()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        offsetY = 0
                    }
                }
        )
    }

    private var iconName: String {
        switch item.style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}