import Foundation
import Observation

/// Tells the Requests tab when something on its list has changed elsewhere
/// (a detail view created a new request, an action banner reflected a delete,
/// etc.). RequestListView observes `lastChange` and reloads on each new value.
@Observable
@MainActor
final class RequestsCoordinator {
    private(set) var lastChange: UUID?

    func markStale() {
        lastChange = UUID()
    }
}
