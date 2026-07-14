#if os(iOS) || os(visionOS)
import SwiftUI

struct ReportIssueMobileForm: View {
    let mediaTitle: String?
    let canSubmitForMedia: Bool
    @Binding var issueType: ReportIssueSheet.IssueType
    @Binding var message: String
    let submitError: String?

    var body: some View {
        Form {
            if let mediaTitle {
                Section("Reporting issue for") {
                    LabeledContent("Title", value: mediaTitle)
                }
            }

            Section("Issue Type") {
                Picker("Issue Type", selection: $issueType) {
                    ForEach(ReportIssueSheet.IssueType.allCases) { type in
                        Label(type.label, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Description") {
                TextField("Describe the problem…", text: $message, axis: .vertical)
                    .lineLimit(5...8)
            }

            if let submitError {
                Section {
                    Label(submitError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if !canSubmitForMedia {
                Section {
                    Label(
                        "This title must be available or requested before an issue can be reported.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
