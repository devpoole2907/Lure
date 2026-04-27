import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var authViewModel: AuthViewModel
    @State private var step: LoginStep = .server

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App icon and title
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)
                    Text("Lure")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Request and discover media")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form
                VStack(spacing: 16) {
                    switch step {
                    case .server:
                        VStack(spacing: 16) {
                            serverForm
                        }
                        .padding()
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    case .credentials:
                        credentialsForm
                    }
                }
                .padding(.horizontal, 24)

                // Error
                if let error = authViewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                Spacer()
            }
            .lureGradientBackground(.blue)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var serverForm: some View {
        TextField("Seerr URL (e.g. http://192.168.1.50:5055)", text: $authViewModel.serverURL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)

        Button {
            Task {
                if await authViewModel.validateServer() {
                    step = .credentials
                }
            }
        } label: {
            Text("Connect")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .glassEffect(.regular.interactive(), in: Capsule())
        .disabled(authViewModel.serverURL.isEmpty)
    }

    @ViewBuilder
    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                if let settings = authViewModel.publicSettings {
                    Text(settings.applicationTitle ?? "Seerr")
                        .font(.headline)
                    Text(authViewModel.serverURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Username", text: $authViewModel.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $authViewModel.password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    _ = await authViewModel.login(modelContext: modelContext)
                }
            } label: {
                if authViewModel.isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .glassEffect(.regular.interactive(), in: Capsule())
            .disabled(authViewModel.username.isEmpty || authViewModel.password.isEmpty || authViewModel.isAuthenticating)

            Button("Back") {
                step = .server
                authViewModel.error = nil
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

private enum LoginStep {
    case server, credentials
}