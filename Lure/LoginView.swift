import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var authViewModel: AuthViewModel
    
    var isModal: Bool = false
    var onComplete: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect Lure to your Seerr instance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("Server") {
                    TextField("Seerr URL (e.g. http://192.168.1.50:5055)", text: $authViewModel.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                if let settings = authViewModel.publicSettings {
                    Section("Connected Server") {
                        LabeledContent("App", value: settings.applicationTitle ?? "Seerr")
                    }
                }
                
                Section("Credentials") {
                    TextField("Username", text: $authViewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $authViewModel.password)
                }
                
                if let error = authViewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            if !authViewModel.canShowCredentials {
                                _ = await authViewModel.validateServer()
                            } else {
                                let success = await authViewModel.login(modelContext: modelContext)
                                if success {
                                    onComplete?()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if authViewModel.isAuthenticating {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Connecting…")
                            } else {
                                Text(authViewModel.canShowCredentials ? "Sign In" : "Connect")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(authViewModel.serverURL.isEmpty || authViewModel.isAuthenticating || (authViewModel.canShowCredentials && (authViewModel.username.isEmpty || authViewModel.password.isEmpty)))
                }
            }
            .navigationTitle("Add Seerr")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isModal {
                        Button("Cancel") {
                            onComplete?()
                        }
                    }
                }
            }
        }
    }
}
