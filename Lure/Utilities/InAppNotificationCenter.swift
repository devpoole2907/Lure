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
        // tvOS presents items as alerts (see `lureBannerAlertHost`); those stay
        // up until the user presses OK, so no auto-dismiss there.
        #if !os(tvOS)
        let id = item.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoDismissDelay)
            guard let self, !Task.isCancelled, currentBanner?.id == id else { return }
            dismiss()
        }
        #endif
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
        #if !os(tvOS)
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
        #endif
    }

    private var iconName: String {
        switch item.style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}

struct LureNotificationOverlay: View {
    let item: LureBannerItem
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
            ZStack(alignment: .bottom) {
                Color.clear
                    .allowsHitTesting(false)

                LureNotificationBanner(item: item, onDismiss: onDismiss)
                    .frame(maxWidth: max(360, proxy.size.width * 0.6))
                    .padding(.bottom, 18)
            }
            #else
            ZStack(alignment: .top) {
                Color.clear
                    .allowsHitTesting(false)

                LureNotificationBanner(item: item, onDismiss: onDismiss)
                    .padding(.top, 8)
            }
            #endif
        }
        .ignoresSafeArea()
    }
}

extension AnyTransition {
    static var lureNotificationBanner: AnyTransition {
        #if os(macOS)
        .move(edge: .bottom).combined(with: .opacity)
        #else
        .move(edge: .top).combined(with: .opacity)
        #endif
    }
}

extension View {
    /// tvOS presentation for the notification center: a standard alert with an
    /// OK button. Floating banners can't receive Siri Remote focus, so on tvOS
    /// they'd be informational-only and unclearable. No-op on other platforms,
    /// where hosts render `LureNotificationOverlay` banners instead.
    @ViewBuilder
    func lureBannerAlertHost(_ center: InAppNotificationCenter?) -> some View {
        #if os(tvOS)
        alert(
            center?.currentBanner?.title ?? "",
            isPresented: Binding(
                get: { center?.currentBanner != nil },
                set: { isPresented in
                    if !isPresented { center?.dismiss() }
                }
            )
        ) {
            Button("OK") { center?.dismiss() }
        } message: {
            if let message = center?.currentBanner?.message {
                Text(message)
            }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
#Preview("Notification Overlay") {
    ZStack {
        Color.gray.opacity(0.16)
            .ignoresSafeArea()

        LureNotificationOverlay(
            item: LureBannerItem(
                title: "Request Failed",
                message: "Network error: cancelled",
                style: .error
            )
        ) {}
    }
    .frame(width: 1280, height: 720)
}
#endif

#if DEBUG && os(iOS)
#Preview("Notification Overlay — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    ZStack {
        LinearGradient(
            colors: [.indigo.opacity(0.35), .black.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        LureNotificationOverlay(
            item: LureBannerItem(
                title: "Added to your requests",
                message: "The server accepted your movie request.",
                style: .success
            )
        ) {}
    }
}
#endif
