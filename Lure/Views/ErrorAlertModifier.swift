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