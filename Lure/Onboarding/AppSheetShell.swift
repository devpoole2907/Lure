import SwiftUI

/// A standard sheet wrapper: navigation title, optional cancel/confirm toolbar
/// items, detents, and a drag indicator. Mirrors Trawl's `AppSheetShell`.
struct AppSheetShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let cancelTitle: String
    let showsCancel: Bool
    let confirmTitle: String?
    let isConfirmDisabled: Bool
    let isConfirmLoading: Bool
    let onConfirm: (() -> Void)?
    let detents: Set<PresentationDetent>
    let dragIndicator: Visibility
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        cancelTitle: String = "Cancel",
        showsCancel: Bool = true,
        confirmTitle: String? = nil,
        isConfirmDisabled: Bool = false,
        isConfirmLoading: Bool = false,
        onConfirm: (() -> Void)? = nil,
        detents: Set<PresentationDetent> = [.large],
        dragIndicator: Visibility = .hidden,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.cancelTitle = cancelTitle
        self.showsCancel = showsCancel
        self.confirmTitle = confirmTitle
        self.isConfirmDisabled = isConfirmDisabled
        self.isConfirmLoading = isConfirmLoading
        self.onConfirm = onConfirm
        self.detents = detents
        self.dragIndicator = dragIndicator
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .appSheetNavigationSubtitle(subtitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if showsCancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(cancelTitle) { dismiss() }
                        }
                    }

                    if let confirmTitle, let onConfirm {
                        ToolbarItem(placement: .confirmationAction) {
                            if isConfirmLoading {
                                ProgressView()
                            } else {
                                Button(confirmTitle, action: onConfirm)
                                    .disabled(isConfirmDisabled)
                            }
                        }
                    }
                }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(dragIndicator)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 540)
        #endif
    }
}

private extension View {
    @ViewBuilder
    func appSheetNavigationSubtitle(_ subtitle: String?) -> some View {
        #if os(macOS)
        if let subtitle {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
