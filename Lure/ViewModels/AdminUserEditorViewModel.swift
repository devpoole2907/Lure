import Foundation
import Observation

@Observable
final class AdminUserEditorViewModel {
    let user: SeerrUser
    var permissionsValue: Int
    var permissionsText: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let apiClient: SeerrAPIClient

    init(user: SeerrUser, apiClient: SeerrAPIClient) {
        self.user = user
        self.apiClient = apiClient
        let value = user.permissions ?? 0
        self.permissionsValue = value
        self.permissionsText = String(value)
    }

    var permissionLevelLabel: String {
        SeerrPermission.permissionLevelLabel(for: permissionsValue)
    }

    var isAdminEnabled: Bool {
        contains(.admin)
    }

    func contains(_ permission: SeerrPermission) -> Bool {
        SeerrPermission.has(permission, in: permissionsValue)
    }

    func set(_ permission: SeerrPermission, enabled: Bool) {
        if enabled {
            permissionsValue |= permission.rawValue
        } else {
            permissionsValue &= ~permission.rawValue
        }
        permissionsText = String(permissionsValue)
    }

    func syncFromText() {
        let filtered = permissionsText.filter(\.isNumber)
        if filtered != permissionsText {
            permissionsText = filtered
        }
        permissionsValue = Int(filtered) ?? 0
    }

    func save() async -> SeerrUser? {
        isSaving = true
        errorMessage = nil

        defer { isSaving = false }

        do {
            let updatedUser = try await apiClient.updateUser(id: user.id, permissions: permissionsValue)
            permissionsValue = updatedUser.permissions ?? permissionsValue
            permissionsText = String(permissionsValue)
            return updatedUser
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
