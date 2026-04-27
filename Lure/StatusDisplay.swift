import SwiftUI

extension LureConstants.MediaStatus {
    var isUserVisible: Bool {
        self != .unknown
    }

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .pending: "Pending"
        case .processing: "Processing"
        case .partiallyAvailable: "Partial"
        case .available: "Available"
        case .deleted: "Deleted"
        }
    }

    var color: Color {
        switch self {
        case .unknown: .secondary
        case .pending: .orange
        case .processing: .purple
        case .partiallyAvailable: .yellow
        case .available: .green
        case .deleted: .red
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .pending: "clock"
        case .processing: "arrow.down.circle"
        case .partiallyAvailable: "circle.lefthalf.filled"
        case .available: "checkmark.circle.fill"
        case .deleted: "trash.circle"
        }
    }
}

extension LureConstants.RequestStatus {
    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .approved: "Approved"
        case .declined: "Declined"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }

    var color: Color {
        switch self {
        case .pending: .orange
        case .approved: .blue
        case .declined: .red
        case .failed: .red
        case .completed: .green
        }
    }
}
