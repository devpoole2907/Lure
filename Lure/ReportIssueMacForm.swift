#if os(macOS)
import SwiftUI

struct ReportIssueMacForm: View {
    let mediaTitle: String?
    let canSubmitForMedia: Bool
    @Binding var issueType: ReportIssueSheet.IssueType
    @Binding var message: String
    let submitError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let mediaTitle {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Reporting issue for", systemImage: "film")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(mediaTitle)
                            .font(.title3.bold())
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Issue Type")
                        .font(.headline)

                    Picker("Issue Type", selection: $issueType) {
                        ForEach(ReportIssueSheet.IssueType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Description")
                        .font(.headline)

                    TextField("Describe the problem…", text: $message, axis: .vertical)
                        .lineLimit(6...9)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.separator, lineWidth: 1)
                        }
                }

                if let submitError {
                    Label(submitError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if !canSubmitForMedia {
                    Label(
                        "This title must be available or requested before an issue can be reported.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
    }
}
#endif
