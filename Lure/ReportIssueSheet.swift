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
            Group {
            #if os(macOS)
            ReportIssueMacForm(
                mediaTitle: mediaTitle,
                canSubmitForMedia: mediaId != nil,
                issueType: $issueType,
                message: $message,
                submitError: submitError
            )
            #elseif os(tvOS)
            ReportIssueTVForm(
                mediaTitle: mediaTitle,
                canSubmitForMedia: mediaId != nil,
                issueType: $issueType,
                message: $message,
                submitError: submitError
            )
            #else
            ReportIssueMobileForm(
                mediaTitle: mediaTitle,
                canSubmitForMedia: mediaId != nil,
                issueType: $issueType,
                message: $message,
                submitError: submitError
            )
            #endif
            }
            .lureNavigationTitle("Report Issue")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit", action: submit)
                            .disabled(isSubmitDisabled)
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
#elseif os(macOS)
        .frame(width: 620, height: 590)
        .background(.regularMaterial)
#elseif os(tvOS)
        .frame(width: 1100, height: 720)
        .background(Color.black.opacity(0.94))
#endif
    }

    private var isSubmitDisabled: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || mediaId == nil
            || isSubmitting
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

#if DEBUG && os(iOS)
#Preview("Report Issue — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    ReportIssueSheet(
        mediaId: PreviewSupport.previewMovieDetail.mediaInfo?.id,
        mediaTitle: PreviewSupport.previewMovieDetail.displayTitle,
        apiClient: PreviewSupport.apiClient
    )
}
#endif

#if DEBUG && os(macOS)
#Preview("Report Issue — macOS") {
    ReportIssueSheet(
        mediaId: PreviewSupport.previewMovieDetail.mediaInfo?.id,
        mediaTitle: PreviewSupport.previewMovieDetail.displayTitle,
        apiClient: PreviewSupport.apiClient
    )
}
#endif

#if DEBUG && os(tvOS)
#Preview("Report Issue — tvOS") {
    ReportIssueSheet(
        mediaId: PreviewSupport.previewMovieDetail.mediaInfo?.id,
        mediaTitle: PreviewSupport.previewMovieDetail.displayTitle,
        apiClient: PreviewSupport.apiClient
    )
    .environment(\.colorScheme, .dark)
}
#endif
