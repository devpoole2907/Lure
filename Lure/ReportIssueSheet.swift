import SwiftUI

struct ReportIssueSheet: View {
    let mediaId: Int?
    let mediaTitle: String?
    let apiClient: SeerrAPIClient

    @Environment(\.dismiss) private var dismiss
    @State private var issueType: IssueType = .other
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var didSubmit = false

    enum IssueType: Int, CaseIterable, Identifiable {
        case video = 1, audio = 2, subtitle = 3, other = 4
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .video: "Video"
            case .audio: "Audio"
            case .subtitle: "Subtitle"
            case .other: "Other"
            }
        }
        var icon: String {
            switch self {
            case .video: "video.slash"
            case .audio: "speaker.slash"
            case .subtitle: "captions.bubble.slash"
            case .other: "questionmark.circle"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let title = mediaTitle {
                        LabeledContent("Title", value: title)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Reporting issue for")
                }

                Section("Issue Type") {
                    Picker("Issue Type", selection: $issueType) {
                        ForEach(IssueType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Description") {
                    TextEditor(text: $message)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Describe the problem...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let error = submitError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if mediaId == nil {
                    Section {
                        Label("This title must be available or requested before an issue can be reported.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Report Issue")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") { submit() }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mediaId == nil || isSubmitting)
                    }
                }
            }
            .alert("Issue Reported", isPresented: $didSubmit) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your issue has been submitted. Thank you for the report.")
            }
        }
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func submit() {
        guard let mediaId else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        submitError = nil

        Task {
            do {
                let body = SeerrCreateIssueBody(issueType: issueType.rawValue, message: trimmed, mediaId: mediaId)
                _ = try await apiClient.createIssue(body)
                isSubmitting = false
                didSubmit = true
            } catch {
                isSubmitting = false
                submitError = error.localizedDescription
            }
        }
    }
}
