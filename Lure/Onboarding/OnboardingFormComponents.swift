import SwiftUI

/// URL entry field with URL keyboard affordances. Mirrors Trawl's `ServerURLField`.
struct ServerURLField: View {
    @Binding var url: String
    var title: String = "Server address"

    var body: some View {
        TextField(title, text: $url)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .textContentType(.URL)
            #endif
            .autocorrectionDisabled()
    }
}

/// Inline form error row. Mirrors Trawl's `ValidationErrorSection`.
struct ValidationErrorSection: View {
    let error: String?

    var body: some View {
        if let error {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(error)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
