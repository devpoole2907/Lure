import Observation
import SwiftUI

struct AdminUserEditorView: View {
    let onSave: (SeerrUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AdminUserEditorViewModel
    @State private var errorAlert: ErrorAlertItem?

    init(user: SeerrUser, apiClient: SeerrAPIClient, onSave: @escaping (SeerrUser) -> Void) {
        self.onSave = onSave
        self._viewModel = State(initialValue: AdminUserEditorViewModel(user: user, apiClient: apiClient))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("User") {
                LabeledContent("Name", value: viewModel.user.displayName)
                if let email = viewModel.user.email {
                    LabeledContent("Email", value: email)
                }
                LabeledContent("Permission Level", value: viewModel.permissionLevelLabel)
                LabeledContent("Bit Flag Value", value: String(viewModel.permissionsValue))
            }

            Section {
                TextField("Permissions", text: $viewModel.permissionsText)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .monospacedDigit()
                    .onChange(of: viewModel.permissionsText) { _, _ in
                        viewModel.syncFromText()
                    }
            } header: {
                Text("Permission Integer")
            } footer: {
                Text("This writes the permission bit-flag integer back to Seerr.")
            }

            if viewModel.isAdminEnabled {
                Section {
                    Label("Admin includes every other permission automatically.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(SeerrPermission.editableGroups, id: \.category.id) { group in
                Section(group.category.rawValue) {
                    ForEach(group.permissions) { permission in
                        Toggle(isOn: Binding(
                            get: { viewModel.contains(permission) },
                            set: { viewModel.set(permission, enabled: $0) }
                        )) {
                            Label(permission.title, systemImage: permission.symbolName)
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            if let updatedUser = await viewModel.save() {
                                onSave(updatedUser)
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.permissionsText.isEmpty)
                }
            }
        }
        .errorAlert(item: $errorAlert)
        .onChange(of: viewModel.errorMessage) { _, message in
            guard let message else { return }
            errorAlert = ErrorAlertItem(title: "Save Failed", message: message)
            viewModel.clearError()
        }
    }
}
