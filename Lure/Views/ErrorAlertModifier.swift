import SwiftUI

struct ErrorAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ErrorAlertModifier: ViewModifier {
    @Binding var item: ErrorAlertItem?

    func body(content: Content) -> some View {
        content
            .alert(item: $item) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
}

extension View {
    func errorAlert(item: Binding<ErrorAlertItem?>) -> some View {
        modifier(ErrorAlertModifier(item: item))
    }
}

#if DEBUG && os(iOS)
#Preview("Error Alert — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    @Previewable @State var error: ErrorAlertItem? = ErrorAlertItem(
        title: "Unable to Connect",
        message: "Check the server address and try again."
    )

    NavigationStack {
        ContentUnavailableView(
            "Server Unavailable",
            systemImage: "network.slash",
            description: Text("Lure couldn't reach your server.")
        )
        .navigationTitle("Requests")
    }
    .errorAlert(item: $error)
}
#endif
