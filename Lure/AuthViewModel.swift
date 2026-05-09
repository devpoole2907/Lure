import Foundation
import Observation
import SwiftData

@Observable
final class AuthViewModel {
    private static let savedServerURLKey = "LureSavedSeerrServerURL"

    var username: String = ""
    var password: String = ""
    var isAuthenticating: Bool = false
    var error: String?
    var currentUser: SeerrUser?
    var isLoggedIn: Bool = false
    var publicSettings: SeerrPublicSettings?
    var serverURL: String = ""

    private(set) var apiClient: SeerrAPIClient?

    var canShowCredentials: Bool {
        apiClient != nil && !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        serverURL = Self.savedServerURL
    }

    // MARK: - Server Validation (deep link or manual entry)

    func validateServer() async -> Bool {
        await configureServer(url: serverURL, shouldSurfaceErrors: true)
    }

    func prepareSavedServerForLogin() async {
        guard apiClient == nil, !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        _ = await configureServer(url: serverURL, shouldSurfaceErrors: false)
    }

    @discardableResult
    private func configureServer(url rawURL: String, shouldSurfaceErrors: Bool) async -> Bool {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            apiClient = nil
            publicSettings = nil
            if shouldSurfaceErrors {
                error = "Server URL is required."
            }
            return false
        }

        let client = SeerrAPIClient(baseURL: url)
        do {
            let settings = try await client.getPublicSettings()
            guard settings.initialized == true else {
                apiClient = nil
                publicSettings = nil
                if shouldSurfaceErrors {
                    error = "This Seerr instance has not been set up yet."
                }
                return false
            }

            serverURL = client.baseURL
            publicSettings = settings
            apiClient = client
            Self.saveServerURL(client.baseURL)
            error = nil
            return true
        } catch {
            apiClient = nil
            publicSettings = nil
            if shouldSurfaceErrors {
                self.error = "Could not connect to Seerr at that URL."
            }
            return false
        }
    }

    // MARK: - Login

    func login(modelContext: ModelContext) async -> Bool {
        guard let client = apiClient else {
            error = "No server configured."
            return false
        }

        guard !username.isEmpty, !password.isEmpty else {
            error = "Username and password are required."
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }
        error = nil

        do {
            let user = try await client.loginJellyfin(username: username, password: password)
            guard let cookie = await client.getSessionCookie() else {
                throw LureError.invalidResponse
            }

            let normalizedServerURL = client.baseURL
            let normalizedServerURLForComparison = normalizedServerURL.lowercased()

            let allProfiles = (try? modelContext.fetch(FetchDescriptor<LureServerProfile>())) ?? []
            let matchingProfiles = allProfiles.filter {
                $0.baseURL.lowercased() == normalizedServerURLForComparison
            }
            let existingWorkerURL = matchingProfiles.compactMap(\.apnsWorkerURL).first

            let profile: LureServerProfile
            if let existingProfile = matchingProfiles.first {
                profile = existingProfile
            } else {
                profile = LureServerProfile(
                    displayName: publicSettings?.applicationTitle ?? normalizedServerURL,
                    serverURL: normalizedServerURL
                )
                modelContext.insert(profile)
            }

            profile.displayName = publicSettings?.applicationTitle ?? normalizedServerURL
            profile.serverURL = normalizedServerURL
            profile.isActive = true
            profile.lastConnected = .now
            if profile.apnsWorkerURL == nil {
                profile.apnsWorkerURL = existingWorkerURL
            }

            for existing in allProfiles where existing.id != profile.id {
                if existing.baseURL.lowercased() == normalizedServerURLForComparison {
                    try? await LureKeychain.shared.delete(key: existing.sessionCookieKey)
                    modelContext.delete(existing)
                } else {
                    existing.isActive = false
                }
            }

            try modelContext.save()
            try await LureKeychain.shared.save(key: profile.sessionCookieKey, value: cookie)
            Self.saveServerURL(normalizedServerURL)

            serverURL = normalizedServerURL
            currentUser = user
            isLoggedIn = true

            if let workerURL = profile.apnsWorkerURL {
                NotificationManager.shared.register(workerURL: workerURL, serverURL: profile.serverURL, username: user.displayName)
            }

            return true
        } catch let error as LureError {
            self.error = error.errorDescription
            currentUser = nil
            isLoggedIn = false
            return false
        } catch {
            self.error = error.localizedDescription
            currentUser = nil
            isLoggedIn = false
            return false
        }
    }

    // MARK: - Session Restore

    func restoreSession(from profile: LureServerProfile) async -> Bool {
        guard let cookie = await LureKeychain.shared.read(key: profile.sessionCookieKey) else {
            return false
        }

        let client = SeerrAPIClient(baseURL: profile.baseURL, sessionCookie: cookie)

        do {
            let user = try await client.getCurrentUser()
            apiClient = client
            serverURL = client.baseURL
            publicSettings = try? await client.getPublicSettings()
            Self.saveServerURL(client.baseURL)
            currentUser = user
            isLoggedIn = true

            if let workerURL = profile.apnsWorkerURL {
                NotificationManager.shared.register(workerURL: workerURL, serverURL: profile.serverURL, username: user.displayName)
            }

            return true
        } catch {
            // Cookie expired or server unreachable — leave VM state untouched
            // so the caller can decide whether to surface a sign-in prompt.
            return false
        }
    }

    // MARK: - Logout

    func logout(profile: LureServerProfile?, modelContext: ModelContext) async {
        try? await apiClient?.logout()
        if let profile {
            if let workerURL = profile.apnsWorkerURL, let token = UserDefaults.standard.string(forKey: "LureDeviceToken") {
                await NotificationManager.shared.unregister(workerURL: workerURL, serverURL: profile.serverURL, deviceToken: token)
            }
            try? await LureKeychain.shared.delete(key: profile.sessionCookieKey)
            profile.isActive = false
            try? modelContext.save()
        }
        apiClient = nil
        currentUser = nil
        isLoggedIn = false
        username = ""
        password = ""
    }

    private static var savedServerURL: String {
        UserDefaults.standard.string(forKey: savedServerURLKey) ?? ""
    }

    private static func saveServerURL(_ url: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        UserDefaults.standard.set(trimmedURL, forKey: savedServerURLKey)
    }
}
