#if os(tvOS)
import SwiftUI

struct ReportIssueTVForm: View {
    let mediaTitle: String?
    let canSubmitForMedia: Bool
    @Binding var issueType: ReportIssueSheet.IssueType
    @Binding var message: String
    let submitError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let mediaTitle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reporting issue for")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(mediaTitle)
                            .font(.title2.bold())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Issue Type")
                        .font(.headline)

                    HStack(spacing: 18) {
                        ForEach(ReportIssueSheet.IssueType.allCases) { type in
                            Button {
                                issueType = type
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: type.icon)
                                    Text(type.label)
                                    Spacer(minLength: 0)
                                    if issueType == type {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityAddTraits(issueType == type ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Description")
                        .font(.headline)

                    TextField("Describe the problem…", text: $message, axis: .vertical)
                        .lineLimit(3...5)
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
            .padding(.horizontal, 46)
            .padding(.vertical, 34)
        }
    }
}
#endif
